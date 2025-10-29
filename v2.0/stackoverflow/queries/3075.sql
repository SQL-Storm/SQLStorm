-- {"query": "3075.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2521}
WITH
answer_stats AS (
    SELECT
        p.Id AS user_id,
        COUNT(*) AS answer_cnt,
        CAST(AVG(p.Score) AS NUMERIC) AS avg_score,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS median_score
    FROM Posts p
    WHERE p.PostTypeId = 2
      AND p.OwnerUserId IS NOT NULL
    GROUP BY p.Id, p.OwnerUserId
),
gold_badges AS (
    SELECT
        b.UserId AS user_id,
        COUNT(*) AS gold_cnt,
        STRING_AGG(DISTINCT b.Name, ', ') AS gold_names
    FROM Badges b
    WHERE b.Class = 1
    GROUP BY b.UserId
),
user_tags AS (
    SELECT
        p.Id AS user_id,
        COUNT(DISTINCT t) AS distinct_tag_cnt,
        STRING_AGG(DISTINCT t, ', ') AS tag_list
    FROM Posts p,
         LATERAL (
           SELECT UNNEST(STRING_TO_ARRAY(TRIM(BOTH '<>' FROM p.Tags), '><')) AS t
         ) AS tags
    WHERE p.PostTypeId = 2
      AND p.OwnerUserId IS NOT NULL
      AND p.Tags IS NOT NULL
    GROUP BY p.Id, p.OwnerUserId, p.Tags
),
post_votes AS (
    SELECT
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS up_votes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS down_votes
    FROM Votes v
    GROUP BY v.PostId
),
user_votes AS (
    SELECT
        p.Id AS user_id,
        COALESCE(SUM(pv.up_votes), 0) AS total_up,
        COALESCE(SUM(pv.down_votes), 0) AS total_down
    FROM Posts p
    LEFT JOIN post_votes pv ON pv.PostId = p.Id
    WHERE p.PostTypeId = 2
      AND p.OwnerUserId IS NOT NULL
    GROUP BY p.Id, p.OwnerUserId
),
qualified_users AS (
    SELECT u.Id
    FROM Users u
    WHERE u.Reputation > 10000
       OR EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1)
)
SELECT
    u.Id AS user_id,
    u.DisplayName,
    u.Reputation,
    COALESCE(a.answer_cnt, 0) AS answer_count,
    COALESCE(a.median_score, 0) AS median_answer_score,
    COALESCE(g.gold_cnt, 0) AS gold_badge_count,
    COALESCE(t.distinct_tag_cnt, 0) AS distinct_tags_answered,
    COALESCE(v.total_up, 0) AS total_up_votes,
    COALESCE(v.total_down, 0) AS total_down_votes,
    CASE
        WHEN COALESCE(v.total_down, 0) = 0 THEN NULL
        ELSE ROUND(CAST(v.total_up AS NUMERIC) / v.total_down, 2)
    END AS up_down_ratio,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS rep_rank
FROM Users u
LEFT JOIN answer_stats a ON a.user_id = u.Id
LEFT JOIN gold_badges g ON g.user_id = u.Id
LEFT JOIN user_tags t ON t.user_id = u.Id
LEFT JOIN user_votes v ON v.user_id = u.Id
WHERE u.Id IN (SELECT Id FROM qualified_users)
  AND (a.answer_cnt IS NULL OR a.answer_cnt > 5)

UNION ALL

SELECT
    u2.Id,
    u2.DisplayName,
    u2.Reputation,
    0 AS answer_count,
    0 AS median_answer_score,
    0 AS gold_badge_count,
    0 AS distinct_tags_answered,
    0 AS total_up_votes,
    0 AS total_down_votes,
    NULL AS up_down_ratio,
    ROW_NUMBER() OVER (ORDER BY u2.Reputation DESC) AS rep_rank
FROM Users u2
WHERE u2.Reputation BETWEEN 9000 AND 10000
  AND NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u2.Id AND p.PostTypeId = 2)
  AND NOT EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = u2.Id AND b.Class = 1)
ORDER BY rep_rank
LIMIT 20;
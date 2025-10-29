-- {"query": "3802.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1751} 

WITH recent_q AS (
    SELECT
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.OwnerUserId,
        unnest(string_to_array(trim(both '<>' FROM p.Tags), '><')) AS tag
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= now() - interval '30 days'
),
tag_agg AS (
    SELECT
        tag,
        COUNT(*)                              AS question_count,
        AVG(p.Score)::numeric(10,2)           AS avg_question_score,
        MAX(p.Score)                          AS max_question_score,
        MIN(p.CreationDate)                   AS first_asked,
        MAX(p.CreationDate)                   AS last_asked
    FROM recent_q p
    GROUP BY tag
),
answer_stats AS (
    SELECT
        q.tag,
        COUNT(a.Id)                           AS answer_count,
        AVG(a.Score)::numeric(10,2)           AS avg_answer_score,
        MAX(a.Score)                          AS max_answer_score
    FROM recent_q q
    JOIN Posts a
          ON a.ParentId = q.Id
         AND a.PostTypeId = 2
    GROUP BY q.tag
),
user_rank AS (
    SELECT
        q.tag,
        q.OwnerUserId,
        u.DisplayName,
        u.Reputation,
        ROW_NUMBER() OVER (PARTITION BY q.tag ORDER BY u.Reputation DESC) AS rank_in_tag
    FROM recent_q q
    JOIN Users u ON u.Id = q.OwnerUserId
),
gold_badge_counts AS (
    SELECT
        t.tag,
        COUNT(b.Id) AS gold_badge_count
    FROM tag_agg t
    LEFT JOIN Badges b
           ON b.UserId IN (SELECT OwnerUserId FROM recent_q WHERE tag = t.tag)
          AND b.Class = 1
    GROUP BY t.tag
),
combined AS (
    SELECT
        ta.tag,
        ta.question_count,
        ta.avg_question_score,
        COALESCE(asb.answer_count,0)        AS answer_count,
        COALESCE(asb.avg_answer_score,0)    AS avg_answer_score,
        gb.gold_badge_count,
        ur.DisplayName                      AS top_user,
        ur.Reputation                       AS top_user_reputation,
        ur.rank_in_tag
    FROM tag_agg ta
    LEFT JOIN answer_stats   asb ON asb.tag = ta.tag
    LEFT JOIN gold_badge_counts gb ON gb.tag = ta.tag
    LEFT JOIN (
        SELECT *
        FROM user_rank
        WHERE rank_in_tag = 1
    ) ur ON ur.tag = ta.tag
)
SELECT *
FROM combined
WHERE question_count >= 5

UNION ALL

SELECT
    t.Tag,
    0                               AS question_count,
    NULL                            AS avg_question_score,
    0                               AS answer_count,
    NULL                            AS avg_answer_score,
    0                               AS gold_badge_count,
    NULL                            AS top_user,
    NULL                            AS top_user_reputation,
    NULL                            AS rank_in_tag
FROM Tags t
WHERE NOT EXISTS (SELECT 1 FROM combined c WHERE c.tag = t.Tag)

ORDER BY question_count DESC,
         avg_question_score DESC NULLS LAST;

-- {"query": "3964.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1821} 

/*  Benchmarking query that touches most tables, uses CTEs, window functions,
    outer joins, correlated subqueries, set operators, complex predicates,
    string aggregation, and NULL handling.                                            */

WITH 
-- Gather per‑user activity stats
user_stats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        COALESCE(u.Reputation,0)                         AS reputation,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1)      AS questions_cnt,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2)      AS answers_cnt,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS up_votes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS down_votes,
        MAX(p.CreationDate)                             AS last_post_dt
    FROM Users u
    LEFT JOIN Posts  p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes  v ON v.PostId = p.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

-- Aggregate badge information per user
badge_stats AS (
    SELECT 
        b.UserId,
        COUNT(*)                                            AS total_badges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END)       AS gold_cnt,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END)       AS silver_cnt,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END)       AS bronze_cnt,
        STRING_AGG(DISTINCT b.Name, ', ') 
            FILTER (WHERE b.Class = 1)                     AS gold_badge_names
    FROM Badges b
    GROUP BY b.UserId
),

-- Identify the highest‑scoring question for each non‑moderator tag
tag_top_q AS (
    SELECT 
        t.TagName,
        t.Count                     AS tag_use_cnt,
        p.Title,
        ROW_NUMBER() OVER (PARTITION BY t.TagName 
                           ORDER BY p.Score DESC NULLS LAST) AS rn
    FROM Tags t
    JOIN Posts p ON p.Id = t.WikiPostId
    WHERE t.IsModeratorOnly = 0
),

-- Users with high reputation but no posts (to stress outer joins + UNION)
inactive_high_rep AS (
    SELECT 
        u.Id,
        u.DisplayName,
        COALESCE(u.Reputation,0)   AS reputation,
        0                         AS questions_cnt,
        0                         AS answers_cnt,
        0                         AS up_votes,
        0                         AS down_votes,
        NULL                      AS last_post_dt
    FROM Users u
    WHERE u.Reputation > 20000
      AND NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)
)

-- Combine active and inactive users
SELECT *
FROM (
    /* Active users with activity data */
    SELECT 
        us.Id,
        us.DisplayName,
        us.reputation,
        us.questions_cnt,
        us.answers_cnt,
        us.up_votes,
        us.down_votes,
        COALESCE(bs.total_badges,0)                         AS total_badges,
        COALESCE(bs.gold_cnt,0)                             AS gold_badges,
        COALESCE(bs.silver_cnt,0)                           AS silver_badges,
        COALESCE(bs.bronze_cnt,0)                           AS bronze_badges,
        bs.gold_badge_names,
        tt.TagName,
        tt.tag_use_cnt,
        tt.Title                                            AS top_question_for_tag,
        us.last_post_dt
    FROM user_stats us
    LEFT JOIN badge_stats bs   ON bs.UserId = us.Id
    LEFT JOIN (
        SELECT TagName, tag_use_cnt, Title
        FROM tag_top_q
        WHERE rn = 1
    ) tt ON TRUE                                               -- cross‑join to surface tag info
    WHERE us.reputation > 10000
      AND (us.questions_cnt + us.answers_cnt) > 0
) 
UNION ALL
(
    /* Inactive high‑rep users – no post‑related columns are NULL */
    SELECT 
        i.Id,
        i.DisplayName,
        i.reputation,
        i.questions_cnt,
        i.answers_cnt,
        i.up_votes,
        i.down_votes,
        0            AS total_badges,
        0            AS gold_badges,
        0            AS silver_badges,
        0            AS bronze_badges,
        NULL         AS gold_badge_names,
        NULL         AS TagName,
        NULL         AS tag_use_cnt,
        NULL         AS top_question_for_tag,
        i.last_post_dt
    FROM inactive_high_rep i
)
ORDER BY reputation DESC, total_badges DESC
OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY;

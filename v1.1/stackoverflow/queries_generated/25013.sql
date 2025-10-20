-- {"query": "25013.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2341} 

WITH
-- Aggregate per user basic post stats
user_stats AS (
    SELECT
        u.Id                                 AS user_id,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1)          AS question_cnt,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2)          AS answer_cnt,
        COALESCE(SUM(p.Score),0)                             AS total_score,
        MAX(p.CreationDate)                                 AS last_post_dt
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

-- Badge totals per user
badge_stats AS (
    SELECT
        b.UserId                           AS user_id,
        COUNT(*)                           AS badge_total,
        COUNT(*) FILTER (WHERE b.Class = 1) AS gold_cnt,
        COUNT(*) FILTER (WHERE b.Class = 2) AS silver_cnt,
        COUNT(*) FILTER (WHERE b.Class = 3) AS bronze_cnt
    FROM Badges b
    GROUP BY b.UserId
),

-- Vote roll‑up per post (up/down only)
post_votes AS (
    SELECT
        v.PostId,
        SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS up_votes,
        SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS down_votes
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY v.PostId
),

-- Vote roll‑up per user (derived from posts)
user_votes AS (
    SELECT
        p.OwnerUserId                                              AS user_id,
        SUM(COALESCE(pv.up_votes,0))                               AS total_up,
        SUM(COALESCE(pv.down_votes,0))                             AS total_down
    FROM Posts p
    LEFT JOIN post_votes pv ON pv.PostId = p.Id
    GROUP BY p.OwnerUserId
),

-- Split tags and count usage per user
user_tag_usage AS (
    SELECT
        p.OwnerUserId                                 AS user_id,
        regexp_split_to_table(p.Tags, '\><')          AS tag,
        COUNT(*)                                      AS tag_cnt
    FROM Posts p
    WHERE p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId, tag
),

-- Rank tags per user, keep only top 3
top_user_tags AS (
    SELECT
        utu.user_id,
        utu.tag,
        utu.tag_cnt,
        ROW_NUMBER() OVER (PARTITION BY utu.user_id
                           ORDER BY utu.tag_cnt DESC, utu.tag) AS rn
    FROM user_tag_usage utu
)

-- Final result set: detailed rows + summary row
SELECT
    us.user_id,
    us.DisplayName,
    us.Reputation,
    us.question_cnt,
    us.answer_cnt,
    us.total_score,
    COALESCE(bs.badge_total,0)      AS badge_total,
    COALESCE(bs.gold_cnt,0)         AS gold_badges,
    COALESCE(bs.silver_cnt,0)       AS silver_badges,
    COALESCE(bs.bronze_cnt,0)       AS bronze_badges,
    ROUND(
        CASE WHEN uv.total_down = 0 THEN NULL
             ELSE (uv.total_up::numeric / NULLIF(uv.total_down,0))
        END, 2)                     AS up_down_ratio,
    COALESCE(us.last_post_dt,'1970-01-01'::timestamp) AS last_activity,
    STRING_AGG(tut.tag, ', ') FILTER (WHERE tut.rn <= 3) AS top_3_tags
FROM user_stats us
LEFT JOIN badge_stats bs   ON bs.user_id = us.user_id
LEFT JOIN user_votes uv    ON uv.user_id = us.user_id
LEFT JOIN top_user_tags tut ON tut.user_id = us.user_id
GROUP BY
    us.user_id, us.DisplayName, us.Reputation,
    us.question_cnt, us.answer_cnt, us.total_score,
    bs.badge_total, bs.gold_cnt, bs.silver_cnt, bs.bronze_cnt,
    uv.total_up, uv.total_down,
    us.last_post_dt
HAVING
    us.Reputation > 1000
    OR (us.question_cnt + us.answer_cnt) > 10
ORDER BY
    us.Reputation DESC,
    badge_total DESC
LIMIT 100

UNION ALL

SELECT
    NULL               AS user_id,
    'SUMMARY'          AS DisplayName,
    NULL               AS Reputation,
    SUM(us.question_cnt)  AS question_cnt,
    SUM(us.answer_cnt)    AS answer_cnt,
    SUM(us.total_score)   AS total_score,
    SUM(COALESCE(bs.badge_total,0)) AS badge_total,
    SUM(COALESCE(bs.gold_cnt,0))    AS gold_badges,
    SUM(COALESCE(bs.silver_cnt,0))  AS silver_badges,
    SUM(COALESCE(bs.bronze_cnt,0))  AS bronze_badges,
    NULL                AS up_down_ratio,
    MAX(us.last_post_dt) AS last_activity,
    NULL                AS top_3_tags
FROM user_stats us
LEFT JOIN badge_stats bs ON bs.user_id = us.user_id
WHERE us.Reputation > 0;

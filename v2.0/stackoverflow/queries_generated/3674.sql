-- {"query": "3674.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2722} 

WITH user_posts AS (
    SELECT
        p.OwnerUserId                               AS user_id,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1)    AS question_cnt,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2)    AS answer_cnt,
        SUM(p.Score) FILTER (WHERE p.PostTypeId = 1) AS question_score,
        SUM(p.Score) FILTER (WHERE p.PostTypeId = 2) AS answer_score,
        MAX(p.CreationDate)                        AS last_post_dt
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
user_badges AS (
    SELECT
        b.UserId                                    AS user_id,
        COUNT(*) FILTER (WHERE b.Class = 1)        AS gold_cnt,
        COUNT(*) FILTER (WHERE b.Class = 2)        AS silver_cnt,
        COUNT(*) FILTER (WHERE b.Class = 3)        AS bronze_cnt,
        COUNT(*) FILTER (WHERE b.TagBased = 1)    AS tag_badge_cnt
    FROM Badges b
    GROUP BY b.UserId
),
post_votes AS (
    SELECT
        v.PostId                                    AS post_id,
        MAX(v.CreationDate)                         AS last_vote_dt
    FROM Votes v
    GROUP BY v.PostId
),
user_last_activity AS (
    SELECT
        u.Id                                         AS user_id,
        GREATEST(
            COALESCE(up.last_post_dt,        TIMESTAMP '1970-01-01'),
            COALESCE(pv.last_vote_dt,        TIMESTAMP '1970-01-01'),
            u.LastAccessDate
        )                                            AS most_recent_dt
    FROM Users u
    LEFT JOIN user_posts up      ON up.user_id = u.Id
    LEFT JOIN (
        SELECT p.OwnerUserId AS owner_id, MAX(pv.last_vote_dt) AS last_vote_dt
        FROM Posts p
        JOIN post_votes pv ON pv.post_id = p.Id
        GROUP BY p.OwnerUserId
    ) pv ON pv.owner_id = u.Id
),
tag_usage AS (
    SELECT
        p.OwnerUserId                                 AS user_id,
        lower(trim(t.tag))                            AS tag,
        COUNT(*)                                      AS tag_cnt,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY COUNT(*) DESC) AS tag_rank
    FROM Posts p
    CROSS JOIN LATERAL regexp_split_to_table(p.Tags, '[><]') AS t(tag)
    WHERE p.PostTypeId = 1
      AND p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId, lower(trim(t.tag))
)
SELECT
    u.Id                                           AS user_id,
    u.DisplayName,
    u.Reputation,
    COALESCE(up.question_cnt,   0)                  AS questions_posted,
    COALESCE(up.answer_cnt,     0)                  AS answers_posted,
    COALESCE(up.question_score,0)                  AS question_score_sum,
    COALESCE(up.answer_score,  0)                  AS answer_score_sum,
    COALESCE(ub.gold_cnt,      0)                  AS gold_badges,
    COALESCE(ub.silver_cnt,    0)                  AS silver_badges,
    COALESCE(ub.bronze_cnt,    0)                  AS bronze_badges,
    COALESCE(ub.tag_badge_cnt, 0)                  AS tag_badges,
    ula.most_recent_dt,
    STRING_AGG(tu.tag || ':' || tu.tag_cnt, ', '
        ORDER BY tu.tag_cnt DESC) FILTER (WHERE tu.tag_rank <= 5) AS top_5_tags,
    CASE
        WHEN u.Reputation > 20000               THEN 'Legend'
        WHEN u.Reputation BETWEEN 10000 AND 19999 THEN 'Expert'
        WHEN u.Reputation BETWEEN 1000  AND 9999  THEN 'Intermediate'
        ELSE 'Newbie'
    END                                            AS reputation_level,
    (COALESCE(up.question_score,0) + COALESCE(up.answer_score,0))::float
        / NULLIF(COALESCE(up.question_cnt,0) + COALESCE(up.answer_cnt,0),0) AS avg_score_per_post
FROM Users u
LEFT JOIN user_posts       up  ON up.user_id = u.Id
LEFT JOIN user_badges      ub  ON ub.user_id = u.Id
LEFT JOIN user_last_activity ula ON ula.user_id = u.Id
LEFT JOIN tag_usage        tu  ON tu.user_id = u.Id
WHERE u.CreationDate < CURRENT_DATE - INTERVAL '1 year'
GROUP BY
    u.Id, u.DisplayName, u.Reputation,
    up.question_cnt, up.answer_cnt,
    up.question_score, up.answer_score,
    ub.gold_cnt, ub.silver_cnt, ub.bronze_cnt, ub.tag_badge_cnt,
    ula.most_recent_dt
HAVING COUNT(tu.tag) > 0
ORDER BY avg_score_per_post DESC NULLS LAST
LIMIT 100

UNION ALL

SELECT
    NULL,
    '--- Summary ---',
    NULL,
    SUM(COALESCE(up.question_cnt,0)),
    SUM(COALESCE(up.answer_cnt,0)),
    SUM(COALESCE(up.question_score,0)),
    SUM(COALESCE(up.answer_score,0)),
    SUM(COALESCE(ub.gold_cnt,0)),
    SUM(COALESCE(ub.silver_cnt,0)),
    SUM(COALESCE(ub.bronze_cnt,0)),
    SUM(COALESCE(ub.tag_badge_cnt,0)),
    NULL,
    NULL,
    NULL,
    (SUM(COALESCE(up.question_score,0)) + SUM(COALESCE(up.answer_score,0)))::float
        / NULLIF(SUM(COALESCE(up.question_cnt,0)) + SUM(COALESCE(up.answer_cnt,0)),0)
FROM Users u
LEFT JOIN user_posts  up ON up.user_id = u.Id
LEFT JOIN user_badges ub ON ub.user_id = u.Id
WHERE u.CreationDate < CURRENT_DATE - INTERVAL '1 year';

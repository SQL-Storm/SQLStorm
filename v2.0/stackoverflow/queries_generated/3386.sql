-- {"query": "3386.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2045} 

WITH
    -- Aggregate post statistics per user
    user_posts AS (
        SELECT
            p.OwnerUserId                      AS user_id,
            COUNT(*)                           AS total_posts,
            COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS questions,
            COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS answers,
            SUM(p.Score)                       AS total_score,
            MAX(p.CreationDate)                AS last_post_date
        FROM Posts p
        WHERE p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId
    ),

    -- Count answers and accepted answers per user
    user_answers AS (
        SELECT
            p.OwnerUserId                      AS user_id,
            COUNT(*)                           AS answer_count,
            COUNT(*) FILTER (WHERE p.Id = p.AcceptedAnswerId) AS accepted_answers
        FROM Posts p
        WHERE p.PostTypeId = 2
          AND p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId
    ),

    -- Badge totals per user, broken out by class
    user_badges AS (
        SELECT
            b.UserId                           AS user_id,
            COUNT(*)                           AS badge_cnt,
            COUNT(*) FILTER (WHERE b.Class = 1) AS gold,
            COUNT(*) FILTER (WHERE b.Class = 2) AS silver,
            COUNT(*) FILTER (WHERE b.Class = 3) AS bronze
        FROM Badges b
        GROUP BY b.UserId
    ),

    -- Explode tags per post and count usage per user
    user_tag_usage AS (
        SELECT
            p.OwnerUserId                      AS user_id,
            TRIM(BOTH '<>' FROM UNNEST(string_to_array(p.Tags, '><'))) AS tag,
            COUNT(*)                           AS tag_use
        FROM Posts p
        WHERE p.Tags IS NOT NULL
          AND p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId, tag
    ),

    -- Pick the most frequent tag per user
    top_tag_per_user AS (
        SELECT
            uta.user_id,
            uta.tag,
            uta.tag_use,
            ROW_NUMBER() OVER (PARTITION BY uta.user_id ORDER BY uta.tag_use DESC) AS rn
        FROM user_tag_usage uta
    ),

    -- Users without any votes of type "Spam" (VoteTypeId = 12)
    eligible_users AS (
        SELECT u.Id
        FROM Users u
        LEFT JOIN Votes v ON v.UserId = u.Id AND v.VoteTypeId = 12
        WHERE v.Id IS NULL
    )

SELECT
    u.Id                                      AS user_id,
    u.DisplayName,
    COALESCE(up.total_posts, 0)                AS total_posts,
    COALESCE(up.questions, 0)                  AS questions,
    COALESCE(up.answers, 0)                    AS answers,
    COALESCE(up.total_score, 0)                AS total_score,
    COALESCE(ua.accepted_answers, 0)           AS accepted_answers,
    COALESCE(ub.badge_cnt, 0)                  AS badge_count,
    COALESCE(ub.gold, 0)                       AS gold_badges,
    COALESCE(ub.silver, 0)                     AS silver_badges,
    COALESCE(ub.bronze, 0)                     AS bronze_badges,
    COALESCE(tt.tag, 'None')                   AS top_tag,
    COALESCE(tt.tag_use, 0)                    AS top_tag_use,
    GREATEST(
        COALESCE(up.last_post_date, TIMESTAMP '1970-01-01'),
        COALESCE(u.LastAccessDate, TIMESTAMP '1970-01-01')
    )                                           AS last_activity,
    CASE
        WHEN u.Reputation > 20000 THEN 'Legend'
        WHEN u.Reputation > 10000 THEN 'Guru'
        WHEN u.Reputation > 5000  THEN 'Expert'
        ELSE 'Novice'
    END                                         AS reputation_tier
FROM Users u
LEFT JOIN user_posts    up  ON up.user_id   = u.Id
LEFT JOIN user_answers  ua  ON ua.user_id   = u.Id
LEFT JOIN user_badges   ub  ON ub.user_id   = u.Id
LEFT JOIN (
    SELECT user_id, tag, tag_use
    FROM top_tag_per_user
    WHERE rn = 1
) tt ON tt.user_id = u.Id
WHERE u.Id IN (SELECT user_id FROM eligible_users)

UNION ALL

-- Synthetic row for benchmarking the engine's handling of a UNION ALL and constant expressions
SELECT
    -1                                            AS user_id,
    'DELETED'                                     AS DisplayName,
    0                                             AS total_posts,
    0                                             AS questions,
    0                                             AS answers,
    0                                             AS total_score,
    0                                             AS accepted_answers,
    0                                             AS badge_count,
    0                                             AS gold_badges,
    0                                             AS silver_badges,
    0                                             AS bronze_badges,
    'None'                                        AS top_tag,
    0                                             AS top_tag_use,
    NULL                                          AS last_activity,
    'Deleted'                                     AS reputation_tier
ORDER BY total_score DESC
LIMIT 100;

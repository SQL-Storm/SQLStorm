WITH
    post_counts AS (
        SELECT
            OwnerUserId,
            SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS question_cnt,
            SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS answer_cnt
        FROM Posts
        GROUP BY OwnerUserId
    ),
    badge_score AS (
        SELECT
            UserId,
            SUM(CASE WHEN badges.class = 1 THEN 5
                     WHEN badges.class = 2 THEN 3
                     WHEN badges.class = 3 THEN 1
                     ELSE 0 END) AS badge_score
        FROM Badges AS badges
        GROUP BY UserId
    ),
    action_counts AS (
        SELECT UserId, COUNT(*) AS total_actions
        FROM (
            SELECT OwnerUserId AS UserId FROM Posts
            UNION ALL
            SELECT UserId FROM Votes
            UNION ALL
            SELECT UserId FROM Comments
        ) a
        GROUP BY UserId
    ),
    user_activity AS (
        SELECT
            u.Id,
            u.DisplayName,
            u.Reputation,
            COALESCE(pc.question_cnt, 0) AS question_cnt,
            COALESCE(pc.answer_cnt, 0) AS answer_cnt,
            COALESCE(b.badge_score, 0) AS badge_score,
            COALESCE(v.total_actions, 0) AS total_actions,
            ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS rn
        FROM Users u
        LEFT JOIN post_counts pc ON u.Id = pc.OwnerUserId
        LEFT JOIN badge_score b ON u.Id = b.UserId
        LEFT JOIN action_counts v ON u.Id = v.UserId
    ),
    tag_usage AS (
        SELECT
            ua.Id,
            STRING_AGG(DISTINCT tag, ', ') AS tags
        FROM user_activity ua
        LEFT JOIN LATERAL (
            SELECT DISTINCT
                regexp_replace(regexp_split_to_table(po.Tags, '><'), '^<|>$', '') AS tag
            FROM Posts po
            WHERE po.OwnerUserId = ua.Id
              AND po.PostTypeId = 1
        ) t ON TRUE
        GROUP BY ua.Id
    ),
    has_accepted AS (
        SELECT
            u.Id AS user_id,
            CASE WHEN EXISTS (
                SELECT 1
                FROM Votes v
                JOIN Posts p ON v.PostId = p.Id
                WHERE v.VoteTypeId = 1
                  AND p.OwnerUserId = u.Id
            ) THEN 1 ELSE 0 END AS accepted_flag
        FROM Users u
    )
SELECT
    ua.Id,
    ua.DisplayName,
    ua.Reputation,
    ua.question_cnt,
    ua.answer_cnt,
    ua.badge_score,
    ua.total_actions,
    COALESCE(tu.tags, 'None') AS tags_used,
    ha.accepted_flag,
    CASE WHEN ua.question_cnt > 0 THEN CAST(ua.question_cnt AS numeric) / NULLIF(ua.answer_cnt, 0) ELSE NULL END AS question_to_answer_ratio
FROM user_activity ua
LEFT JOIN tag_usage tu ON ua.Id = tu.Id
LEFT JOIN has_accepted ha ON ua.Id = ha.user_id
WHERE ua.Reputation > 1000
  AND (ua.question_cnt > 10 OR ua.answer_cnt > 50)
  AND (ha.accepted_flag = 1 OR ha.accepted_flag IS NULL)
ORDER BY ua.rn
LIMIT 20;
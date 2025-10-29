WITH 
user_posts AS (
    SELECT 
        p.OwnerUserId                           AS user_id,
        COUNT(*)                                AS post_cnt,
        SUM(p.Score)                            AS total_score,
        AVG(p.Score)                            AS avg_score,
        MIN(p.CreationDate)                     AS first_post_dt,
        MAX(p.LastActivityDate)                 AS last_activity_dt
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
user_badges AS (
    SELECT 
        b.UserId                                 AS user_id,
        COUNT(*)                                 AS badge_cnt,
        SUM(CASE b.Class WHEN 1 THEN 3 
                         WHEN 2 THEN 2 
                         ELSE 1 END)          AS badge_weight
    FROM Badges b
    GROUP BY b.UserId
),
user_votes AS (
    SELECT 
        p.OwnerUserId                           AS user_id,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1
                 WHEN v.VoteTypeId = 3 THEN -1
                 ELSE 0 END)                     AS net_votes
    FROM Posts p
    JOIN Votes v ON v.PostId = p.Id
    WHERE p.OwnerUserId IS NOT NULL
      AND v.VoteTypeId IN (2,3)
    GROUP BY p.OwnerUserId
),
user_comments AS (
    SELECT 
        u.Id                                    AS user_id,
        MAX(c.CreationDate)                     AS last_comment_dt
    FROM Users u
    LEFT JOIN Comments c ON c.UserId = u.Id
    GROUP BY u.Id
),
tag_usage AS (
    SELECT 
        TRIM(BOTH '<>' FROM split_part(p.Tags, '><', 1)) AS tag,
        COUNT(*)                                         AS tag_q_cnt
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Tags IS NOT NULL
    GROUP BY TRIM(BOTH '<>' FROM split_part(p.Tags, '><', 1))
),
user_dupes AS (
    SELECT DISTINCT 
        p.OwnerUserId                AS user_id,
        1                            AS has_duplicate
    FROM Posts p
    JOIN PostLinks pl 
        ON pl.PostId = p.Id
       AND pl.LinkTypeId = 3
    WHERE p.OwnerUserId IS NOT NULL
),
user_recent_activity AS (
    SELECT 
        u.Id                                AS user_id,
        GREATEST(
            COALESCE(up.last_activity_dt, TIMESTAMP '1970-01-01'),
            COALESCE(uc.last_comment_dt, TIMESTAMP '1970-01-01')
        )                                   AS most_recent_dt
    FROM Users u
    LEFT JOIN user_posts up   ON up.user_id = u.Id
    LEFT JOIN user_comments uc ON uc.user_id = u.Id
),
user_summary AS (
    SELECT 
        u.Id                                          AS user_id,
        u.DisplayName,
        u.Reputation,
        COALESCE(up.post_cnt,0)                       AS post_cnt,
        COALESCE(up.total_score,0)                    AS total_score,
        COALESCE(up.avg_score,0)                      AS avg_score,
        COALESCE(ub.badge_cnt,0)                      AS badge_cnt,
        COALESCE(ub.badge_weight,0)                   AS badge_weight,
        COALESCE(uv.net_votes,0)                      AS net_votes,
        uc.last_comment_dt,
        COALESCE(ud.has_duplicate,0)                  AS has_duplicate,
        ura.most_recent_dt,
        (u.Reputation * 0.6
         + COALESCE(ub.badge_weight,0) * 100
         + COALESCE(uv.net_votes,0) * 10
         + COALESCE(up.total_score,0) * 0.5)          AS activity_score
    FROM Users u
    LEFT JOIN user_posts up      ON up.user_id = u.Id
    LEFT JOIN user_badges ub     ON ub.user_id = u.Id
    LEFT JOIN user_votes uv      ON uv.user_id = u.Id
    LEFT JOIN user_comments uc   ON uc.user_id = u.Id
    LEFT JOIN user_dupes ud      ON ud.user_id = u.Id
    LEFT JOIN user_recent_activity ura ON ura.user_id = u.Id
    WHERE u.CreationDate < (CAST('2024-10-01' AS date) - INTERVAL '1 year')
      AND (u.Location IS NOT NULL OR u.AboutMe IS NOT NULL)
)

SELECT * FROM (
    SELECT 
        us.user_id,
        us.DisplayName,
        us.Reputation,
        us.post_cnt,
        us.total_score,
        us.avg_score,
        us.badge_cnt,
        us.badge_weight,
        us.net_votes,
        us.last_comment_dt,
        us.has_duplicate,
        us.most_recent_dt,
        ROW_NUMBER() OVER (ORDER BY us.activity_score DESC, us.Reputation DESC) AS rank_by_activity
    FROM user_summary us
    WHERE us.activity_score > 0
    ORDER BY rank_by_activity
    LIMIT 100
) t

UNION ALL

SELECT 
    NULL::INTEGER        AS user_id,
    NULL::VARCHAR        AS DisplayName,
    NULL::INTEGER        AS Reputation,
    0                    AS post_cnt,
    0                    AS total_score,
    0                    AS avg_score,
    0                    AS badge_cnt,
    0                    AS badge_weight,
    0                    AS net_votes,
    NULL::TIMESTAMP      AS last_comment_dt,
    0                    AS has_duplicate,
    NULL::TIMESTAMP      AS most_recent_dt,
    0                    AS rank_by_activity
ORDER BY rank_by_activity;
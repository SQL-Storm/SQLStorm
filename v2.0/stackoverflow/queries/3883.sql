WITH 
user_posts AS (
    SELECT 
        u.Id                                   AS user_id,
        u.DisplayName                          AS user_name,
        COALESCE(u.Reputation,0)               AS reputation,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS questions_cnt,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS answers_cnt,
        SUM(CASE WHEN p.PostTypeId = 1 THEN COALESCE(p.Score,0) ELSE 0 END) AS questions_score_sum,
        SUM(CASE WHEN p.PostTypeId = 2 THEN COALESCE(p.Score,0) ELSE 0 END) AS answers_score_sum,
        MAX(p.CreationDate)                   AS last_post_date
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

user_badges AS (
    SELECT 
        b.UserId                                   AS user_id,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END)        AS gold_cnt,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END)        AS silver_cnt,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END)        AS bronze_cnt,
        SUM(CASE WHEN b.TagBased = TRUE THEN 1 ELSE 0 END)  AS tag_based_cnt,
        MAX(b.Date)                                AS latest_badge_date
    FROM Badges b
    GROUP BY b.UserId
),

recent_votes AS (
    SELECT 
        v.PostId,
        v.VoteTypeId,
        v.UserId,
        v.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY v.PostId ORDER BY v.CreationDate DESC) AS vote_rank
    FROM Votes v
    WHERE v.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30 days')
),

top_voted_posts AS (
    SELECT 
        p.OwnerUserId                         AS user_id,
        p.Id                                   AS post_id,
        p.Title                                AS post_title,
        SUM(CASE WHEN rv.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvote_cnt,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY SUM(CASE WHEN rv.VoteTypeId = 2 THEN 1 ELSE 0 END) DESC) AS rn
    FROM Posts p
    LEFT JOIN recent_votes rv ON rv.PostId = p.Id AND rv.VoteTypeId = 2
    WHERE p.PostTypeId IN (1,2)
    GROUP BY p.OwnerUserId, p.Id, p.Title
),

post_tags AS (
    SELECT 
        p.Id                                 AS post_id,
        UNNEST(STRING_TO_ARRAY(TRIM(BOTH '<>' FROM COALESCE(p.Tags,'')), '><')) AS tag_name
    FROM Posts p
    WHERE p.PostTypeId = 1
),

tag_popularity AS (
    SELECT 
        t.tag_name,
        COUNT(*) AS tag_usage_cnt,
        SUM(p.Score) AS total_score,
        MAX(p.CreationDate) AS latest_used
    FROM post_tags t
    JOIN Posts p ON p.Id = t.post_id
    GROUP BY t.tag_name
),

users_without_posts AS (
    SELECT u.Id AS user_id, u.DisplayName AS user_name
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE p.Id IS NULL
),

all_users AS (
    SELECT up.user_id, up.user_name, 'active'   AS status FROM user_posts up
    UNION ALL
    SELECT uwp.user_id, uwp.user_name, 'inactive' AS status FROM users_without_posts uwp
)

SELECT 
    au.user_id,
    au.user_name,
    COALESCE(up.reputation,0) AS reputation,
    COALESCE(up.questions_cnt,0) AS questions_cnt,
    COALESCE(up.answers_cnt,0) AS answers_cnt,
    COALESCE(up.questions_score_sum,0) + COALESCE(up.answers_score_sum,0) AS total_score,
    COALESCE(ub.gold_cnt,0) AS gold_cnt,
    COALESCE(ub.silver_cnt,0) AS silver_cnt,
    COALESCE(ub.bronze_cnt,0) AS bronze_cnt,
    COALESCE(ub.tag_based_cnt,0) AS tag_based_cnt,
    tvp.post_title,
    COALESCE(tvp.upvote_cnt,0) AS upvote_cnt,
    tp.tag_name,
    tp.tag_usage_cnt,
    tp.tag_total_score,
    CASE 
        WHEN up.last_post_date IS NULL THEN 'Never posted'
        WHEN up.last_post_date < (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year') THEN 'Stale'
        ELSE 'Active'
    END AS activity_status,
    au.status
FROM all_users au
LEFT JOIN user_posts up      ON up.user_id = au.user_id
LEFT JOIN user_badges ub     ON ub.user_id = au.user_id
LEFT JOIN top_voted_posts tvp 
       ON tvp.user_id = au.user_id AND tvp.rn = 1
LEFT JOIN LATERAL (
    SELECT pt.tag_name, COUNT(*) OVER () AS tag_usage_cnt, SUM(p.Score) OVER () AS tag_total_score
    FROM post_tags pt
    JOIN Posts p ON p.Id = pt.post_id
    WHERE p.OwnerUserId = au.user_id
    ORDER BY p.Score DESC
    LIMIT 1
) tp ON true
ORDER BY 
    COALESCE(up.reputation,0) DESC,
    COALESCE(up.questions_cnt,0) DESC,
    COALESCE(up.answers_cnt,0) DESC;
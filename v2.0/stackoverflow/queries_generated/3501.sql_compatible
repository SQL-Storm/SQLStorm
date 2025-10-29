WITH
user_activity AS (
    SELECT
        u.Id                     AS user_id,
        u.DisplayName            AS display_name,
        u.Reputation,
        COUNT(p.Id)              AS total_posts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS question_score,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS answer_score,
        MAX(p.CreationDate)      AS latest_post_date,
        MAX(
            (SELECT MAX(ph.CreationDate)
               FROM PostHistory ph
               WHERE ph.PostId = p.Id
                 AND ph.PostHistoryTypeId IN (4,5,6)
            )
        )                         AS latest_edit_date
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
badge_stats AS (
    SELECT
        b.UserId                 AS user_id,
        COUNT(*)                 AS badge_count,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_badges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver_badges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze_badges,
        STRING_AGG(DISTINCT b.Name, ', ')           AS badge_names
    FROM Badges b
    GROUP BY b.UserId
),
post_votes AS (
    SELECT
        v.PostId,
        SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS up_votes,
        SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS down_votes
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY v.PostId
),
post_latest_comment AS (
    SELECT
        c.PostId,
        MAX(c.CreationDate) AS last_comment_date
    FROM Comments c
    GROUP BY c.PostId
),
tag_usage AS (
    SELECT
        t.TagName,
        COUNT(p.Id) AS posts_with_tag,
        SUM(p.Score) AS total_score,
        AVG(p.ViewCount) AS avg_views
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE ( '%' || '<' || t.TagName || '>' || '%' )
    GROUP BY t.TagName
),
combined_users AS (
    SELECT
        ua.user_id,
        ua.display_name,
        ua.reputation,
        ua.total_posts,
        ua.question_score,
        ua.answer_score,
        ua.latest_post_date,
        ua.latest_edit_date,
        bs.badge_count,
        bs.gold_badges,
        bs.silver_badges,
        bs.bronze_badges,
        bs.badge_names
    FROM user_activity ua
    LEFT JOIN badge_stats bs ON bs.user_id = ua.user_id

    UNION ALL

    SELECT
        NULL                         AS user_id,
        NULL                         AS display_name,
        NULL                         AS reputation,
        0                            AS total_posts,
        0                            AS question_score,
        0                            AS answer_score,
        NULL                         AS latest_post_date,
        NULL                         AS latest_edit_date,
        bs.badge_count,
        bs.gold_badges,
        bs.silver_badges,
        bs.bronze_badges,
        bs.badge_names
    FROM badge_stats bs
    WHERE NOT EXISTS (SELECT 1 FROM user_activity ua WHERE ua.user_id = bs.user_id)
),
ranked_users AS (
    SELECT
        cu.*,
        ROW_NUMBER() OVER (ORDER BY
            COALESCE(cu.reputation,0) DESC,
            COALESCE(cu.gold_badges,0)   DESC,
            COALESCE(cu.silver_badges,0) DESC,
            COALESCE(cu.bronze_badges,0) DESC,
            COALESCE(cu.question_score,0) + COALESCE(cu.answer_score,0) DESC
        ) AS user_rank,
        (COALESCE(cu.reputation,0) * 0.5 +
         COALESCE(cu.gold_badges,0) * 1000 +
         COALESCE(cu.silver_badges,0) * 500 +
         COALESCE(cu.bronze_badges,0) * 100 +
         COALESCE(cu.question_score,0) * 2 +
         COALESCE(cu.answer_score,0) * 3) AS composite_score
    FROM combined_users cu
)
SELECT
    ru.user_id,
    ru.display_name,
    ru.reputation,
    ru.total_posts,
    ru.question_score,
    ru.answer_score,
    ru.badge_count,
    ru.gold_badges,
    ru.silver_badges,
    ru.bronze_badges,
    ru.badge_names,
    ru.user_rank,
    ru.composite_score,
    GREATEST(
        COALESCE(ru.latest_post_date, CAST('1970-01-01' AS timestamp)),
        COALESCE(ru.latest_edit_date, CAST('1970-01-01' AS timestamp)),
        COALESCE(
            (SELECT MAX(plc.last_comment_date)
               FROM post_latest_comment plc
               JOIN Posts p ON p.Id = plc.PostId
               WHERE p.OwnerUserId = ru.user_id),
            CAST('1970-01-01' AS timestamp)
        )
    ) AS most_recent_activity,
    COALESCE(
        (SELECT tu.TagName
           FROM tag_usage tu
           JOIN Posts p ON p.Tags LIKE ( '%' || '<' || tu.TagName || '>' || '%' )
           WHERE p.OwnerUserId = ru.user_id
           GROUP BY tu.TagName, tu.posts_with_tag
           ORDER BY tu.posts_with_tag DESC
           LIMIT 1),
        'None'
    ) AS top_tag,
    CONCAT(
        COALESCE(ru.display_name, 'Anonymous'),
        ' (Rank ',
        COALESCE(CAST(ru.user_rank AS text), 'N/A'),
        ')'
    ) AS display_rank
FROM ranked_users ru
WHERE ru.user_rank <= 100
ORDER BY ru.user_rank;
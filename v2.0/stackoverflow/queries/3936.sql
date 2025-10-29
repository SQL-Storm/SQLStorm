WITH
usr_agg AS (
    SELECT
        u.Id                         AS user_id,
        u.DisplayName                AS display_name,
        u.Reputation,
        COUNT(p.Id)                  AS total_posts,
        COALESCE(SUM(p.Score),0)     AS sum_score,
        AVG(p.Score)                 FILTER (WHERE p.Score IS NOT NULL) AS avg_score,
        MAX(p.CreationDate)          AS latest_post_date,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS upvote_cnt,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS downvote_cnt
    FROM Users u
    LEFT JOIN Posts p       ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v       ON v.PostId = p.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
badge_agg AS (
    SELECT
        b.UserId                AS user_id,
        COUNT(*)                FILTER (WHERE b.Class = 1) AS gold_cnt,
        COUNT(*)                FILTER (WHERE b.Class = 2) AS silver_cnt,
        COUNT(*)                FILTER (WHERE b.Class = 3) AS bronze_cnt,
        COUNT(*)                AS total_badges
    FROM Badges b
    GROUP BY b.UserId
),
tag_agg AS (
    SELECT
        p.OwnerUserId                                           AS user_id,
        LOWER(t.tag)                                            AS tag,
        COUNT(*)                                                AS tag_usage
    FROM Posts p,
    LATERAL (
        SELECT regexp_split_to_table(COALESCE(p.Tags, ''), '<|>') AS tag
    ) t
    WHERE p.OwnerUserId IS NOT NULL
      AND p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId, LOWER(t.tag)
),
top_tag AS (
    SELECT
        user_id,
        tag,
        tag_usage,
        ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY tag_usage DESC, tag) AS rn
    FROM tag_agg
),
close_activity AS (
    SELECT
        u.Id                                     AS user_id,
        (
            SELECT COUNT(*)
            FROM PostHistory ph
            WHERE ph.PostHistoryTypeId = 10
              AND ph.UserId = u.Id
              AND ph.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '30 days')
        )                                        AS closes_last_30d
    FROM Users u
),
engagement AS (
    SELECT
        ua.user_id,
        ua.display_name,
        ua.reputation,
        ua.total_posts,
        ua.sum_score,
        ua.avg_score,
        COALESCE(b.gold_cnt,0) * 10
      + COALESCE(b.silver_cnt,0) * 5
      + COALESCE(b.bronze_cnt,0) * 2
      + COALESCE(ua.upvote_cnt,0) - COALESCE(ua.downvote_cnt,0)
      + COALESCE(ca.closes_last_30d,0) * 3
      + COALESCE(tt.tag_usage,0) * 0.5                                   AS engagement_score,
        COALESCE(tt.tag, 'none')                                          AS top_tag,
        COALESCE(tt.tag_usage,0)                                          AS top_tag_usage,
        ROW_NUMBER() OVER (ORDER BY
            (COALESCE(ua.reputation,0) +
             COALESCE(ua.total_posts,0) * 2 +
             COALESCE(ua.sum_score,0) * 0.1) DESC)                       AS overall_rank,
        COALESCE(b.total_badges,0)                                        AS total_badges,
        COALESCE(b.gold_cnt,0)                                            AS gold_cnt,
        COALESCE(b.silver_cnt,0)                                          AS silver_cnt,
        COALESCE(b.bronze_cnt,0)                                          AS bronze_cnt
    FROM usr_agg ua
    LEFT JOIN badge_agg b   ON b.user_id = ua.user_id
    LEFT JOIN close_activity ca ON ca.user_id = ua.user_id
    LEFT JOIN top_tag tt    ON tt.user_id = ua.user_id AND tt.rn = 1
)

SELECT
    e.user_id,
    e.display_name,
    e.reputation,
    e.total_posts,
    e.avg_score,
    e.engagement_score,
    e.top_tag,
    e.top_tag_usage,
    e.overall_rank,
    CASE
        WHEN e.reputation >= 20000 THEN 'high_rep'
        WHEN e.gold_cnt >= 5          THEN 'gold_holder'
        WHEN e.total_badges >= 100    THEN 'badge_collector'
        ELSE 'regular'
    END AS user_category
FROM engagement e
LEFT JOIN badge_agg b ON b.user_id = e.user_id
WHERE e.engagement_score IS NOT NULL
  AND e.display_name IS NOT NULL

UNION ALL

SELECT
    u.Id                              AS user_id,
    u.DisplayName                     AS display_name,
    u.Reputation,
    0                                 AS total_posts,
    NULL                              AS avg_score,
    (COALESCE(b.gold_cnt,0) * 10
     + COALESCE(b.silver_cnt,0) * 5
     + COALESCE(b.bronze_cnt,0) * 2)  AS engagement_score,
    'none'                            AS top_tag,
    0                                 AS top_tag_usage,
    NULL                              AS overall_rank,
    'badge_only'                      AS user_category
FROM Users u
JOIN badge_agg b ON b.user_id = u.Id
WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)

ORDER BY engagement_score DESC
LIMIT 150;
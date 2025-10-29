WITH 
user_metrics AS (
    SELECT 
        u.Id                     AS user_id,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id)              FILTER (WHERE p.PostTypeId = 1) AS question_count,
        COUNT(p.Id)              FILTER (WHERE p.PostTypeId = 2) AS answer_count,
        COALESCE(SUM(p.Score),0) AS total_score,
        AVG(p.Score)             FILTER (WHERE p.Score IS NOT NULL) AS avg_score,
        MAX(p.CreationDate)      AS last_post_date,
        MAX(COALESCE(p.LastActivityDate, p.CreationDate)) AS last_activity_date,
        COUNT(DISTINCT v.VoteTypeId) AS distinct_vote_types,
        u.CreationDate
    FROM Users u
    LEFT JOIN Posts p    ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v    ON v.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
badge_counts AS (
    SELECT 
        b.UserId                 AS user_id,
        COUNT(*)                 AS total_badges,
        COUNT(*) FILTER (WHERE b.Class = 1) AS gold_badges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS silver_badges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS bronze_badges,
        COUNT(*) FILTER (WHERE b.TagBased = TRUE) AS tag_based_badges
    FROM Badges b
    GROUP BY b.UserId
),
recent_votes AS (
    SELECT 
        v.UserId                 AS user_id,
        SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS upvotes_last30d,
        SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS downvotes_last30d,
        COUNT(*)                 AS total_votes_last30d
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.CreationDate >= (DATE '2024-10-01' - INTERVAL '30' DAY)
    GROUP BY v.UserId
),
user_tag_popularity AS (
    SELECT
        u.Id                                   AS user_id,
        t.TagName,
        COUNT(*)                               AS tag_usage_count,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY COUNT(*) DESC) AS tag_rank
    FROM Users u
    JOIN Posts p      ON p.OwnerUserId = u.Id AND p.PostTypeId = 1 AND p.Tags IS NOT NULL
    CROSS JOIN LATERAL (
        SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag
    ) AS tag_exploded(tag)
    JOIN Tags t       ON t.TagName = tag_exploded.tag
    GROUP BY u.Id, t.TagName
),
latest_comment_per_post AS (
    SELECT 
        c.PostId,
        c.Text AS latest_comment_text,
        c.CreationDate AS comment_date
    FROM Comments c
    WHERE c.CreationDate = (
        SELECT MAX(c2.CreationDate)
        FROM Comments c2
        WHERE c2.PostId = c.PostId
    )
),
combined AS (
    SELECT 
        um.user_id,
        um.DisplayName,
        um.Reputation,
        um.question_count,
        um.answer_count,
        um.total_score,
        um.avg_score,
        um.last_post_date,
        um.last_activity_date,
        um.distinct_vote_types,
        bc.total_badges,
        bc.gold_badges,
        bc.silver_badges,
        bc.bronze_badges,
        bc.tag_based_badges,
        rv.upvotes_last30d,
        rv.downvotes_last30d,
        rv.total_votes_last30d,
        (COALESCE(um.question_count,0) * 2 + COALESCE(um.answer_count,0) * 3 +
         COALESCE(um.total_score,0) * 0.5 + COALESCE(bc.total_badges,0) * 4) 
         AS engagement_score,
        CASE 
            WHEN um.last_activity_date IS NULL THEN um.CreationDate
            ELSE um.last_activity_date
        END AS effective_last_activity
    FROM user_metrics um
    LEFT JOIN badge_counts bc   ON bc.user_id = um.user_id
    LEFT JOIN recent_votes rv   ON rv.user_id = um.user_id
)

SELECT 
    c.user_id,
    c.DisplayName,
    c.Reputation,
    c.question_count,
    c.answer_count,
    c.total_score,
    ROUND(c.avg_score,2)           AS avg_score,
    c.last_post_date,
    c.effective_last_activity,
    c.distinct_vote_types,
    c.total_badges,
    c.gold_badges,
    c.silver_badges,
    c.bronze_badges,
    c.tag_based_badges,
    c.upvotes_last30d,
    c.downvotes_last30d,
    c.total_votes_last30d,
    c.engagement_score,
    RANK() OVER (ORDER BY c.engagement_score DESC) AS engagement_rank,
    STRING_AGG(utp.TagName, ', ' ORDER BY utp.tag_usage_count DESC) 
        FILTER (WHERE utp.tag_rank <= 3) AS top_3_tags,
    CASE 
        WHEN COALESCE(c.total_badges,0) = 0 AND (COALESCE(c.question_count,0) + COALESCE(c.answer_count,0)) > 0 THEN 'ActiveNoBadge'
        ELSE NULL
    END AS activity_flag,
    lc.latest_comment_text,
    lc.comment_date
FROM combined c
LEFT JOIN user_tag_popularity utp   ON utp.user_id = c.user_id
LEFT JOIN LATERAL (
    SELECT lc.*
    FROM latest_comment_per_post lc
    JOIN Posts p ON p.Id = lc.PostId
    WHERE p.OwnerUserId = c.user_id AND p.PostTypeId = 1
    ORDER BY p.CreationDate DESC
    LIMIT 1
) lc ON TRUE
GROUP BY 
    c.user_id, c.DisplayName, c.Reputation, c.question_count, c.answer_count,
    c.total_score, c.avg_score, c.last_post_date, c.effective_last_activity,
    c.distinct_vote_types, c.total_badges, c.gold_badges, c.silver_badges,
    c.bronze_badges, c.tag_based_badges, c.upvotes_last30d, c.downvotes_last30d,
    c.total_votes_last30d, c.engagement_score, lc.latest_comment_text, lc.comment_date
ORDER BY c.engagement_score DESC
LIMIT 100;
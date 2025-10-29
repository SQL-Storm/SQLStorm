WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ViewCount,
        p.ClosedDate,
        p.CommunityOwnedDate,
        ROW_NUMBER() OVER(PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate DESC) AS rn_by_score_desc,
        DENSE_RANK() OVER(ORDER BY p.ViewCount DESC) AS dr_by_view_count,
        SUM(p.Score) OVER(PARTITION BY p.PostTypeId) AS total_score_by_type,
        AVG(p.CommentCount) OVER(PARTITION BY p.OwnerUserId) AS avg_comments_per_user_post,
        CASE
            WHEN p.FavoriteCount > 100 AND p.Score > 50 THEN 'Highly Favored & Scored'
            WHEN p.AnswerCount > 10 AND p.Score > 20 THEN 'Popular & Highly Answered'
            WHEN p.ViewCount > 10000 THEN 'Widely Viewed'
            ELSE 'Standard'
        END AS post_engagement_category,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN CAST(p.ClosedDate AS DATE) - CAST(p.CreationDate AS DATE)
            ELSE NULL
        END AS days_to_close,
        COALESCE(p.OwnerUserId, -1) AS safe_owner_user_id,
        LOWER(COALESCE(u.Location, 'Unknown')) AS normalized_location,
        LEFT(COALESCE(u.DisplayName, 'Anonymous'), 3) AS short_display_name,
        CASE WHEN p.Tags LIKE '%<sql>%' THEN 'SQL-Related' ELSE 'Other' END AS sql_tag_status
    FROM Posts p
    INNER JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.CreationDate >= TIMESTAMP '2020-01-01' AND p.Score > -5
),
UserActivity AS (
    SELECT
        UserId,
        COUNT(Id) AS comment_count,
        MAX(CreationDate) AS last_comment_date
    FROM Comments
    WHERE UserId IS NOT NULL
    GROUP BY UserId
),
PostHistorySummary AS (
    SELECT
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 4 THEN 1 END) AS title_edit_count,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 5 THEN 1 END) AS body_edit_count,
        MAX(ph.CreationDate) AS last_edit_date
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5)
    GROUP BY ph.PostId
)
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.OwnerDisplayName,
    rp.PostCreationDate,
    rp.Score,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.ViewCount,
    rp.post_engagement_category,
    rp.days_to_close,
    rp.normalized_location,
    rp.short_display_name,
    rp.sql_tag_status,
    COALESCE(ua.comment_count, 0) AS user_total_comments,
    CASE
        WHEN rp.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        WHEN rp.ClosedDate IS NOT NULL THEN 'Closed: ' || (CAST(rp.ClosedDate AS DATE) - CAST(rp.PostCreationDate AS DATE)) || ' days'
        WHEN rp.rn_by_score_desc <= 5 AND rp.PostTypeId = 1 THEN 'Top Question'
        ELSE 'Regular Post'
    END AS post_status_tag,
    phs.title_edit_count,
    phs.body_edit_count,
    CASE
        WHEN phs.last_edit_date IS NOT NULL AND phs.last_edit_date > rp.PostCreationDate THEN 'History Overrides Post Edit'
        WHEN phs.last_edit_date IS NOT NULL THEN 'Edited Post Available'
        ELSE 'No Recent Edits Tracked'
    END AS edit_tracking_status,
    COALESCE(rp.total_score_by_type, 0) AS overall_type_score_sum,
    COALESCE(rp.avg_comments_per_user_post, 0.0) AS avg_user_post_comments,
    CASE
        WHEN rp.OwnerUserId IS NULL THEN 'No Owner'
        WHEN EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = rp.OwnerUserId AND b.Name LIKE '%Expert%') THEN 'Expert User'
        ELSE 'Regular User'
    END AS owner_badge_status,
    (rp.Score * 1.0 / NULLIF(rp.ViewCount, 0)) AS score_per_view_ratio,
    EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = rp.PostId AND pl.LinkTypeId = 3) AS has_duplicate_link
FROM RankedPosts rp
LEFT JOIN UserActivity ua ON rp.OwnerUserId = ua.UserId
LEFT JOIN PostHistorySummary phs ON rp.PostId = phs.PostId
WHERE rp.dr_by_view_count <= 100
GROUP BY
    rp.PostId,
    rp.PostTypeName,
    rp.OwnerDisplayName,
    rp.PostCreationDate,
    rp.Score,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.ViewCount,
    rp.post_engagement_category,
    rp.days_to_close,
    rp.normalized_location,
    rp.short_display_name,
    rp.sql_tag_status,
    ua.comment_count,
    rp.CommunityOwnedDate,
    rp.ClosedDate,
    rp.rn_by_score_desc,
    rp.PostTypeId,
    phs.title_edit_count,
    phs.body_edit_count,
    phs.last_edit_date,
    rp.total_score_by_type,
    rp.avg_comments_per_user_post,
    rp.OwnerUserId,
    rp.Score,
    rp.ViewCount,
    rp.PostCreationDate,
    rp.PostId,
    rp.PostCreationDate,
    rp.Score
ORDER BY rp.PostCreationDate DESC, rp.Score DESC;
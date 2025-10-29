WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS rn_by_score_views,
        AVG(CAST(p.Score AS DOUBLE PRECISION)) OVER (PARTITION BY p.PostTypeId) AS avg_score_by_type,
        COUNT(c.Id) OVER (PARTITION BY p.Id) AS comment_count_for_post,
        CASE
            WHEN p.Tags LIKE '%<sql>%' THEN 'SQL Related'
            WHEN p.Tags LIKE '%<performance>%' THEN 'Performance Related'
            WHEN p.Tags LIKE '%<optimization>%' THEN 'Optimization Related'
            ELSE 'Other'
        END AS tag_category
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
      AND p.CreationDate >= (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '365 days')
),
PostVoteAnalysis AS (
    SELECT
        p.Id AS PostId,
        COUNT(CASE WHEN vt.Name = 'UpMod' THEN 1 END) AS upvotes,
        COUNT(CASE WHEN vt.Name = 'DownMod' THEN 1 END) AS downvotes,
        COUNT(CASE WHEN vt.Name = 'Favorite' THEN 1 END) AS favorites,
        SUM(CASE WHEN vt.Name = 'BountyStart' THEN COALESCE(v.BountyAmount, 0) ELSE 0 END) AS total_bounty_amount
    FROM Posts p
    JOIN Votes v ON p.Id = v.PostId
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE p.PostTypeId = 1 -- Only for Questions
    GROUP BY p.Id
)
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.OwnerDisplayName,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.rn_by_score_views,
    rp.avg_score_by_type,
    rp.comment_count_for_post,
    pva.upvotes,
    pva.downvotes,
    pva.favorites,
    pva.total_bounty_amount,
    CASE
        WHEN rp.Score > rp.avg_score_by_type * 1.5 THEN 'Above Average Score'
        WHEN rp.Score < rp.avg_score_by_type * 0.5 THEN 'Below Average Score'
        ELSE 'Average Score'
    END AS score_performance_category,
    rp.tag_category,
    CASE
        WHEN rp.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN rp.FavoriteCount > 100 THEN 'Highly Favorited'
        WHEN rp.ViewCount > 10000 THEN 'Highly Viewed'
        ELSE 'Standard'
    END AS post_status_category,
    UPPER(SUBSTRING(rp.OwnerDisplayName FROM 1 FOR 3)) AS owner_initials,
    CASE WHEN rp.OwnerUserId IS NULL THEN 'Deleted User' ELSE 'Active User' END AS owner_status,
    COALESCE(rp.FavoriteCount, 0) + COALESCE(rp.AnswerCount, 0) AS engagement_score
FROM RankedPosts rp
LEFT JOIN PostVoteAnalysis pva ON rp.PostId = pva.PostId
WHERE rp.rn_by_score_views <= 100 -- Top 100 posts by score/views within each type
  AND (rp.tag_category = 'SQL Related' OR rp.tag_category = 'Performance Related')

UNION ALL

SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.OwnerDisplayName,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.rn_by_score_views,
    rp.avg_score_by_type,
    rp.comment_count_for_post,
    pva.upvotes,
    pva.downvotes,
    pva.favorites,
    pva.total_bounty_amount,
    CASE
        WHEN rp.Score > rp.avg_score_by_type * 1.5 THEN 'Above Average Score'
        WHEN rp.Score < rp.avg_score_by_type * 0.5 THEN 'Below Average Score'
        ELSE 'Average Score'
    END AS score_performance_category,
    rp.tag_category,
    CASE
        WHEN rp.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN rp.FavoriteCount > 100 THEN 'Highly Favorited'
        WHEN rp.ViewCount > 10000 THEN 'Highly Viewed'
        ELSE 'Standard'
    END AS post_status_category,
    UPPER(SUBSTRING(rp.OwnerDisplayName FROM 1 FOR 3)) AS owner_initials,
    CASE WHEN rp.OwnerUserId IS NULL THEN 'Deleted User' ELSE 'Active User' END AS owner_status,
    COALESCE(rp.FavoriteCount, 0) + COALESCE(rp.AnswerCount, 0) AS engagement_score
FROM RankedPosts rp
LEFT JOIN PostVoteAnalysis pva ON rp.PostId = pva.PostId
WHERE rp.rn_by_score_views <= 50 -- Top 50 posts for other categories
  AND rp.tag_category = 'Other'
ORDER BY PostTypeName, rn_by_score_views;
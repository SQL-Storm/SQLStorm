WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.AnswerCount,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER(PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn_by_type_date,
        LAG(p.Score, 1, 0) OVER(PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS PreviousDayScore,
        SUM(p.ViewCount) OVER(PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeViewsByUser,
        CASE
            WHEN p.AnswerCount > 5 AND p.Score > 50 THEN 'Highly Engaged Question'
            WHEN p.AnswerCount <= 1 AND p.Score < 5 THEN 'Low Engagement Post'
            ELSE 'Standard Post'
        END AS EngagementCategory,
        (SELECT COUNT(c.Id) FROM Comments c WHERE c.PostId = p.Id) AS CommentCountForPost,
        (SELECT STRING_AGG(CAST(v.VoteTypeId AS VARCHAR), ',') FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId IN (2, 3)) AS VoteTypesForPost,
        p.ClosedDate,
        p.CommunityOwnedDate,
        p.Tags
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '1 year')
),
UserPostSummary AS (
    SELECT
        rp.OwnerUserId,
        COUNT(rp.PostId) AS TotalPostsByUser,
        AVG(rp.PostScore) AS AverageScoreByUser,
        MAX(rp.PostCreationDate) AS LastPostDateByUser
    FROM RankedPosts rp
    WHERE rp.OwnerUserId IS NOT NULL
    GROUP BY rp.OwnerUserId
),
PostHistoryAgg AS (
    SELECT
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 5 THEN 1 END) AS BodyEditCount,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 4 THEN 1 END) AS TitleEditCount,
        MAX(ph.CreationDate) AS LastEditDateForPost
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5) AND ph.PostId IN (SELECT PostId FROM RankedPosts)
    GROUP BY ph.PostId
)
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.PostCreationDate,
    rp.PostScore,
    rp.AnswerCount,
    rp.rn_by_type_date,
    rp.PreviousDayScore,
    rp.CumulativeViewsByUser,
    rp.EngagementCategory,
    COALESCE(ups.TotalPostsByUser, 0) AS TotalPostsByOwner,
    COALESCE(ups.AverageScoreByUser, 0.0) AS AverageScoreOfOwner,
    COALESCE(ups.LastPostDateByUser, rp.PostCreationDate) AS OwnerLastPostDate,
    COALESCE(pha.BodyEditCount, 0) AS TotalBodyEdits,
    COALESCE(pha.TitleEditCount, 0) AS TotalTitleEdits,
    COALESCE(pha.LastEditDateForPost, rp.PostCreationDate) AS LastPostModificationDate,
    rp.CommentCountForPost,
    rp.VoteTypesForPost,
    (SELECT u.DisplayName FROM Users u WHERE u.Id = rp.OwnerUserId) AS OwnerDisplayName,
    CASE
        WHEN rp.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN rp.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Active'
    END AS PostStatus,
    CASE
        WHEN rp.Tags LIKE '%<sql>%' THEN 'SQL Related'
        WHEN rp.Tags LIKE '%<performance>%' THEN 'Performance Related'
        ELSE 'Other'
    END AS TagFocus
FROM RankedPosts rp
LEFT JOIN UserPostSummary ups ON rp.OwnerUserId = ups.OwnerUserId
LEFT JOIN PostHistoryAgg pha ON rp.PostId = pha.PostId
WHERE rp.rn_by_type_date <= 100
UNION ALL
SELECT
    CAST(NULL AS BIGINT) AS PostId,
    'Summary' AS PostTypeName,
    CAST(NULL AS TIMESTAMP) AS PostCreationDate,
    AVG(rp.PostScore) AS PostScore,
    SUM(rp.AnswerCount) AS AnswerCount,
    COUNT(*) AS rn_by_type_date,
    AVG(rp.PreviousDayScore) AS PreviousDayScore,
    SUM(rp.CumulativeViewsByUser) AS CumulativeViewsByUser,
    CAST(NULL AS VARCHAR) AS EngagementCategory,
    CAST(NULL AS INTEGER) AS TotalPostsByOwner,
    CAST(NULL AS DOUBLE PRECISION) AS AverageScoreOfOwner,
    CAST(NULL AS TIMESTAMP) AS OwnerLastPostDate,
    CAST(NULL AS INTEGER) AS TotalBodyEdits,
    CAST(NULL AS INTEGER) AS TotalTitleEdits,
    CAST(NULL AS TIMESTAMP) AS LastPostModificationDate,
    CAST(NULL AS INTEGER) AS CommentCountForPost,
    CAST(NULL AS VARCHAR) AS VoteTypesForPost,
    CAST(NULL AS VARCHAR) AS OwnerDisplayName,
    CAST(NULL AS VARCHAR) AS PostStatus,
    CAST(NULL AS VARCHAR) AS TagFocus
FROM RankedPosts rp
WHERE rp.rn_by_type_date <= 100;
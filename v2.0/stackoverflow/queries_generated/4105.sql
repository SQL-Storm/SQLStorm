-- {"query": "4105.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1020} 

WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        u.DisplayName AS EditorDisplayName,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    JOIN Users u ON ph.UserId = u.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
),
UserPostActivity AS (
    SELECT
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        SUM(p.ViewCount) AS TotalViewsReceived,
        AVG(p.Score) AS AverageScore,
        MAX(p.CreationDate) AS LastPostCreationDate
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId <> -1
    GROUP BY p.OwnerUserId
),
AggregatedComments AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS CommentCount,
        SUM(c.Score) AS TotalCommentScore,
        COUNT(CASE WHEN c.UserId IS NULL THEN 1 END) AS AnonymousCommentCount
    FROM Comments c
    GROUP BY c.PostId
),
PostLinkAnalysis AS (
    SELECT
        pl.PostId,
        COUNT(DISTINCT pl.RelatedPostId) AS LinkedPostCount,
        SUM(CASE WHEN lt.Name = 'Duplicate' THEN 1 ELSE 0 END) AS DuplicateLinkCount
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    GROUP BY pl.PostId
)
SELECT
    p.Id AS PostId,
    pt.Name AS PostType,
    p.Title,
    COALESCE(u.DisplayName, p.OwnerDisplayName) AS PostOwnerDisplayName,
    COALESCE(up.TotalPostsOwned, 0) AS OwnerTotalPosts,
    COALESCE(up.TotalViewsReceived, 0) AS OwnerTotalViews,
    COALESCE(up.AverageScore, 0.0) AS OwnerAverageScore,
    p.CreationDate AS PostCreationDate,
    p.LastActivityDate,
    p.Score AS PostScore,
    p.ViewCount AS PostViewCount,
    p.AnswerCount,
    p.CommentCount AS PostCommentCount,
    COALESCE(ac.CommentCount, 0) AS AggregatedCommentCount,
    COALESCE(ac.TotalCommentScore, 0) AS AggregatedTotalCommentScore,
    COALESCE(ac.AnonymousCommentCount, 0) AS AggregatedAnonymousCommentCount,
    COALESCE(pla.LinkedPostCount, 0) AS TotalLinkedPosts,
    COALESCE(pla.DuplicateLinkCount, 0) AS TotalDuplicateLinks,
    CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Active'
    END AS PostStatus,
    CASE
        WHEN rpe.rn = 1 THEN rpe.EditorDisplayName
        ELSE 'No Recent Edit by This User'
    END AS LastEditorDisplayNameForPost,
    (p.FavoriteCount * 1.5 + p.AnswerCount * 1.0 - p.ViewCount * 0.01) AS WeightedPostScore,
    UPPER(SUBSTRING(p.ContentLicense FROM 1 FOR 3)) AS LicensePrefix,
    CAST(p.CreationDate AS DATE) AS PostCreationDateOnly
FROM Posts p
JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN UserPostActivity up ON p.OwnerUserId = up.OwnerUserId
LEFT JOIN AggregatedComments ac ON p.Id = ac.PostId
LEFT JOIN PostLinkAnalysis pla ON p.Id = pla.PostId
LEFT JOIN RankedPostEdits rpe ON p.Id = rpe.PostId AND rpe.rn = 1
WHERE p.Score > 10
   OR (p.AnswerCount > 5 AND p.ViewCount > 1000)
   OR EXISTS (SELECT 1 FROM Comments c WHERE c.PostId = p.Id AND c.Score > 5)
ORDER BY WeightedPostScore DESC, p.LastActivityDate DESC
LIMIT 1000;

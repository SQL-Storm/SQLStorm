-- {"query": "4928.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1788} 

WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.CreationDate AS EditDate,
        ph.PostHistoryTypeId,
        ph.Comment AS EditComment,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edits to Title, Body, or Tags
),
UserPostActivity AS (
    SELECT
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        SUM(p.Score) AS TotalScoreOfOwnedPosts,
        AVG(p.ViewCount) AS AvgViewCountOfOwnedPosts
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
    GROUP BY p.OwnerUserId
),
PostActivitySummary AS (
    SELECT
        p.Id AS PostId,
        pt.Name AS PostType,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.FavoriteCount,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
        CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END AS IsCommunityOwned,
        CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END AS HasAcceptedAnswer,
        COUNT(c.Id) AS CommentCountOnPost,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId IN (1, 2, 3, 5) -- Questions, Answers, Wiki, TagWiki
    GROUP BY
        p.Id,
        pt.Name,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.CommunityOwnedDate,
        p.AcceptedAnswerId
),
UserContributions AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        MAX(b.Date) AS LastBadgeDate,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate
)
SELECT
    pas.PostId,
    pas.PostType,
    pas.OwnerUserId,
    uc.DisplayName AS OwnerDisplayName,
    uc.Reputation AS OwnerReputation,
    pas.CreationDate AS PostCreationDate,
    pas.Score,
    pas.ViewCount,
    pas.FavoriteCount,
    pas.IsClosed,
    pas.IsCommunityOwned,
    pas.HasAcceptedAnswer,
    pas.CommentCountOnPost,
    pas.UpVoteCount,
    pas.DownVoteCount,
    CASE
        WHEN pas.Score > 100 AND pas.FavoriteCount > 10 THEN 'Highly Valued'
        WHEN pas.Score > 10 AND pas.CommentCountOnPost > 5 THEN 'Engaging'
        WHEN pas.IsClosed = 1 AND pas.Score < 0 THEN 'Problematic'
        ELSE 'Standard'
    END AS PostStatusCategory,
    COALESCE(rpe.EditDate, pas.PostCreationDate) AS LastActivityOrEditDate,
    COALESCE(rpe.EditComment, 'No specific edit comment') AS LatestEditComment,
    upa.TotalPostsOwned,
    upa.TotalScoreOfOwnedPosts,
    upa.AvgViewCountOfOwnedPosts,
    uc.BadgeCount,
    uc.GoldBadges,
    uc.SilverBadges,
    uc.BronzeBadges,
    CASE
        WHEN uc.Reputation > 10000 AND uc.GoldBadges >= 3 THEN 'High Rep & Authority'
        WHEN uc.Reputation BETWEEN 1000 AND 10000 AND uc.SilverBadges >= 5 THEN 'Mid Rep & Experience'
        ELSE 'Other User Tier'
    END AS UserTier,
    LAG(pas.Score, 1, 0) OVER (PARTITION BY pas.OwnerUserId ORDER BY pas.CreationDate) AS PreviousPostScore,
    LEAD(pas.Score, 1, 0) OVER (PARTITION BY pas.OwnerUserId ORDER BY pas.CreationDate) AS NextPostScore,
    SUM(pas.Score) OVER (PARTITION BY pas.OwnerUserId ORDER BY pas.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeScoreForUser,
    ROUND(AVG(pas.ViewCount) OVER (PARTITION BY pas.OwnerUserId ORDER BY pas.CreationDate ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2) AS RollingAvgViewCountForUser
FROM PostActivitySummary pas
LEFT JOIN UserPostActivity upa ON pas.OwnerUserId = upa.OwnerUserId
LEFT JOIN UserContributions uc ON pas.OwnerUserId = uc.UserId
LEFT JOIN RankedPostEdits rpe ON pas.PostId = rpe.PostId AND rpe.rn = 1
WHERE pas.OwnerUserId IS NOT NULL
UNION
SELECT
    NULL AS PostId,
    'Summary' AS PostType,
    NULL AS OwnerUserId,
    NULL AS OwnerDisplayName,
    NULL AS OwnerReputation,
    NULL AS PostCreationDate,
    SUM(Score) AS Score,
    SUM(ViewCount) AS ViewCount,
    SUM(FavoriteCount) AS FavoriteCount,
    SUM(IsClosed) AS IsClosed,
    SUM(IsCommunityOwned) AS IsCommunityOwned,
    SUM(HasAcceptedAnswer) AS HasAcceptedAnswer,
    SUM(CommentCountOnPost) AS CommentCountOnPost,
    SUM(UpVoteCount) AS UpVoteCount,
    SUM(DownVoteCount) AS DownVoteCount,
    'Overall' AS PostStatusCategory,
    NULL AS LastActivityOrEditDate,
    'Overall Summary' AS LatestEditComment,
    COUNT(DISTINCT upa.OwnerUserId) AS TotalPostsOwned,
    SUM(upa.TotalScoreOfOwnedPosts) AS TotalScoreOfOwnedPosts,
    AVG(upa.AvgViewCountOfOwnedPosts) AS AvgViewCountOfOwnedPosts,
    COUNT(DISTINCT uc.UserId) AS BadgeCount,
    SUM(uc.GoldBadges) AS GoldBadges,
    SUM(uc.SilverBadges) AS SilverBadges,
    SUM(uc.BronzeBadges) AS BronzeBadges,
    'Global Summary' AS UserTier,
    NULL AS PreviousPostScore,
    NULL AS NextPostScore,
    NULL AS CumulativeScoreForUser,
    NULL AS RollingAvgViewCountForUser
FROM PostActivitySummary pas
LEFT JOIN UserPostActivity upa ON pas.OwnerUserId = upa.OwnerUserId
LEFT JOIN UserContributions uc ON pas.OwnerUserId = uc.UserId;

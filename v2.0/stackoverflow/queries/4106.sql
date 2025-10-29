-- {"query": "4106.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1503}
WITH RankedUserEdits AS (
    SELECT
        ph.UserId,
        ph.PostId,
        ph.CreationDate AS EditDate,
        ph.PostHistoryTypeId,
        ROW_NUMBER() OVER(PARTITION BY ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
),
LatestEdits AS (
    SELECT
        UserId,
        PostId,
        EditDate,
        PostHistoryTypeId
    FROM RankedUserEdits
    WHERE rn <= 5
),
UserPostInteraction AS (
    SELECT
        COALESCE(p.OwnerUserId, c.UserId) AS UserId,
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.CommentCount AS PostCommentCount,
        p.FavoriteCount AS PostFavoriteCount,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
        CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END AS IsCommunityOwned,
        CASE WHEN EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) THEN 1 ELSE 0 END AS IsDuplicateLink,
        c.Id AS CommentId,
        c.Score AS CommentScore,
        c.CreationDate AS CommentCreationDate,
        CASE WHEN c.UserId IS NOT NULL THEN 1 ELSE 0 END AS HasUserCommented
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.OwnerUserId IS NOT NULL OR c.UserId IS NOT NULL
),
UserReputationChange AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.UpVotes AS TotalUpVotes,
        u.DownVotes AS TotalDownVotes,
        u.Views AS TotalViews,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
        ROW_NUMBER() OVER(ORDER BY u.Reputation DESC) AS UserRankByReputation
    FROM Users u
),
PostEngagement AS (
    SELECT
        upi.UserId,
        upi.PostId,
        upi.PostTypeId,
        upi.PostCreationDate,
        upi.PostScore,
        upi.PostViewCount,
        upi.PostCommentCount,
        upi.PostFavoriteCount,
        upi.IsClosed,
        upi.IsCommunityOwned,
        upi.IsDuplicateLink,
        COUNT(upi.CommentId) AS TotalCommentsOnPost,
        SUM(upi.CommentScore) AS TotalCommentScoreOnPost,
        MAX(CASE WHEN upi.HasUserCommented = 1 THEN upi.CommentCreationDate ELSE NULL END) AS LastCommentDateByThisUser,
        CASE WHEN MAX(upi.HasUserCommented) IS NULL THEN 0 ELSE 1 END AS UserHasCommentedOnThisPost
    FROM UserPostInteraction upi
    GROUP BY
        upi.UserId,
        upi.PostId,
        upi.PostTypeId,
        upi.PostCreationDate,
        upi.PostScore,
        upi.PostViewCount,
        upi.PostCommentCount,
        upi.PostFavoriteCount,
        upi.IsClosed,
        upi.IsCommunityOwned,
        upi.IsDuplicateLink
)
SELECT
    urc.UserId,
    urc.Reputation,
    urc.TotalUpVotes,
    urc.TotalDownVotes,
    urc.TotalViews,
    urc.GoldBadges,
    urc.SilverBadges,
    urc.BronzeBadges,
    urc.UserRankByReputation,
    SUM(pe.PostScore) AS TotalScoreOfUserPosts,
    AVG(pe.PostViewCount) AS AverageViewCountOfUserPosts,
    COUNT(DISTINCT pe.PostId) AS NumberOfUserPosts,
    SUM(CASE WHEN pe.PostTypeId = 1 THEN 1 ELSE 0 END) AS NumberOfQuestions,
    SUM(CASE WHEN pe.PostTypeId = 2 THEN 1 ELSE 0 END) AS NumberOfAnswers,
    SUM(pe.TotalCommentsOnPost) AS TotalCommentsMadeByUser,
    AVG(pe.TotalCommentScoreOnPost) AS AverageCommentScoreOnUserPosts,
    COUNT(DISTINCT le.PostId) AS NumberOfPostsEditedByThisUser,
    MAX(pe.PostCreationDate) AS LatestPostCreationDate,
    MIN(pe.PostCreationDate) AS EarliestPostCreationDate,
    COUNT(DISTINCT CASE WHEN pe.IsClosed = 1 THEN pe.PostId ELSE NULL END) AS NumberOfClosedPosts,
    COUNT(DISTINCT CASE WHEN pe.IsDuplicateLink = 1 THEN pe.PostId ELSE NULL END) AS NumberOfDuplicatePosts,
    CAST(SUM(pe.PostFavoriteCount) AS DECIMAL(18, 2)) / NULLIF(COUNT(pe.PostId), 0) AS AverageFavoriteCount,
    SUM(CASE WHEN pe.IsCommunityOwned = 1 THEN 1 ELSE 0 END) AS CommunityOwnedPostsCount,
    0 + (COALESCE(SUM(pe.PostCommentCount), 0) + COUNT(pe.PostId)) AS TotalInteractions_PostsPlusComments
FROM UserReputationChange urc
JOIN PostEngagement pe ON urc.UserId = pe.UserId
LEFT JOIN LatestEdits le ON urc.UserId = le.UserId AND pe.PostId = le.PostId
WHERE urc.Reputation > 10000 AND urc.TotalUpVotes > 5000
GROUP BY
    urc.UserId,
    urc.Reputation,
    urc.TotalUpVotes,
    urc.TotalDownVotes,
    urc.TotalViews,
    urc.GoldBadges,
    urc.SilverBadges,
    urc.BronzeBadges,
    urc.UserRankByReputation
HAVING COUNT(DISTINCT pe.PostId) > 10 AND SUM(pe.PostScore) > 1000
ORDER BY urc.Reputation DESC, SUM(pe.PostScore) DESC;
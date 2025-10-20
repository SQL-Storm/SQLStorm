WITH HighRepUsers AS (
    SELECT Id, DisplayName, Reputation, CreationDate
    FROM Users
    WHERE Reputation > 10000
), UserPostStats AS (
    SELECT 
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS AnswersProvided,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.ViewCount) AS MaxViewCount,
        SUM(p.FavoriteCount) AS TotalFavorites
    FROM Posts p
    JOIN HighRepUsers hru ON p.OwnerUserId = hru.Id
    GROUP BY p.OwnerUserId
), UserCommentStats AS (
    SELECT 
        c.UserId,
        COUNT(DISTINCT c.Id) AS TotalComments,
        AVG(c.Score) AS AvgCommentScore
    FROM Comments c
    JOIN HighRepUsers hru ON c.UserId = hru.Id
    GROUP BY c.UserId
), UserVoteStats AS (
    SELECT 
        v.UserId,
        COUNT(DISTINCT CASE WHEN vt.Name = 'UpMod' THEN v.Id ELSE NULL END) AS UpvotesGiven,
        COUNT(DISTINCT CASE WHEN vt.Name = 'DownMod' THEN v.Id ELSE NULL END) AS DownvotesGiven,
        COUNT(DISTINCT CASE WHEN vt.Name = 'BountyStart' THEN v.Id ELSE NULL END) AS BountiesStarted
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    JOIN HighRepUsers hru ON v.UserId = hru.Id
    GROUP BY v.UserId
), UserBadgeStats AS (
    SELECT 
        b.UserId,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id ELSE NULL END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.TagBased = TRUE THEN b.Id ELSE NULL END) AS TagBasedBadges
    FROM Badges b
    JOIN HighRepUsers hru ON b.UserId = hru.Id
    GROUP BY b.UserId
)
SELECT 
    hru.Id,
    hru.DisplayName,
    hru.Reputation,
    ups.TotalPosts,
    ups.QuestionsAsked,
    ups.AnswersProvided,
    ups.AvgPostScore,
    ups.MaxViewCount,
    ups.TotalFavorites,
    ucs.TotalComments,
    ucs.AvgCommentScore,
    uvs.UpvotesGiven,
    uvs.DownvotesGiven,
    uvs.BountiesStarted,
    ubs.TotalBadges,
    ubs.GoldBadges,
    ubs.TagBasedBadges,
    RANK() OVER (ORDER BY hru.Reputation DESC) AS ReputationRank,
    DENSE_RANK() OVER (ORDER BY COALESCE(ups.TotalPosts, 0) DESC) AS PostActivityRank
FROM HighRepUsers hru
LEFT JOIN UserPostStats ups ON hru.Id = ups.UserId
LEFT JOIN UserCommentStats ucs ON hru.Id = ucs.UserId
LEFT JOIN UserVoteStats uvs ON hru.Id = uvs.UserId
LEFT JOIN UserBadgeStats ubs ON hru.Id = ubs.UserId
GROUP BY
    hru.Id,
    hru.DisplayName,
    hru.Reputation,
    ups.TotalPosts,
    ups.QuestionsAsked,
    ups.AnswersProvided,
    ups.AvgPostScore,
    ups.MaxViewCount,
    ups.TotalFavorites,
    ucs.TotalComments,
    ucs.AvgCommentScore,
    uvs.UpvotesGiven,
    uvs.DownvotesGiven,
    uvs.BountiesStarted,
    ubs.TotalBadges,
    ubs.GoldBadges,
    ubs.TagBasedBadges
ORDER BY 
    hru.Reputation DESC, 
    COALESCE(ups.TotalPosts, 0) DESC, 
    COALESCE(ucs.TotalComments, 0) DESC 
LIMIT 100;
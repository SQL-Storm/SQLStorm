-- {"query": "53070.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 797} 

WITH UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.LastActivityDate) AS LastPostActivity,
        SUM(p.ViewCount) AS TotalViews,
        SUM(p.FavoriteCount) AS TotalFavorites
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.Reputation, u.CreationDate
    HAVING COUNT(p.Id) > 50
),
BadgeStats AS (
    SELECT 
        UserId,
        COUNT(CASE WHEN Class = 1 THEN Id END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN Id END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN Id END) AS BronzeBadges,
        MAX(Date) AS LatestBadgeDate
    FROM Badges
    GROUP BY UserId
    HAVING COUNT(Id) > 10
),
VoteStats AS (
    SELECT 
        p.OwnerUserId AS UserId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpvotesReceived,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownvotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) AS TotalBountiesStarted
    FROM Votes v
    JOIN Posts p ON v.PostId = p.Id
    WHERE v.CreationDate > '2020-01-01'
    GROUP BY p.OwnerUserId
),
CommentStats AS (
    SELECT 
        UserId,
        COUNT(Id) AS CommentCount,
        AVG(Score) AS AvgCommentScore
    FROM Comments
    WHERE CreationDate > '2020-01-01'
    GROUP BY UserId
    HAVING COUNT(Id) > 20
),
TagStats AS (
    SELECT 
        p.OwnerUserId AS UserId,
        STRING_AGG(DISTINCT t.TagName, ', ') AS TopTags
    FROM Posts p
    JOIN Tags t ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    WHERE p.PostTypeId = 1 AND p.Score > 10
    GROUP BY p.OwnerUserId
    HAVING COUNT(DISTINCT t.TagName) > 5
)
SELECT 
    ups.UserId,
    ups.Reputation,
    ups.UserCreationDate,
    ups.QuestionCount,
    ups.AnswerCount,
    ups.AvgPostScore,
    ups.LastPostActivity,
    ups.TotalViews,
    ups.TotalFavorites,
    bs.GoldBadges,
    bs.SilverBadges,
    bs.BronzeBadges,
    bs.LatestBadgeDate,
    vs.UpvotesReceived,
    vs.DownvotesReceived,
    vs.TotalBountiesStarted,
    cs.CommentCount,
    cs.AvgCommentScore,
    ts.TopTags,
    RANK() OVER (ORDER BY ups.Reputation DESC, bs.GoldBadges DESC) AS OverallRank
FROM UserPostStats ups
LEFT JOIN BadgeStats bs ON ups.UserId = bs.UserId
LEFT JOIN VoteStats vs ON ups.UserId = vs.UserId
LEFT JOIN CommentStats cs ON ups.UserId = cs.UserId
LEFT JOIN TagStats ts ON ups.UserId = ts.UserId
WHERE bs.GoldBadges > 5 OR vs.UpvotesReceived > 1000
ORDER BY OverallRank
LIMIT 100;

-- {"query": "58093.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 1390} 

WITH ActiveUsers AS (
    SELECT Id, DisplayName, Reputation, CreationDate
    FROM Users
    WHERE Reputation > 10000
    AND CreationDate BETWEEN '2010-01-01' AND '2023-12-31'
),
UserPosts AS (
    SELECT 
        p.OwnerUserId, 
        COUNT(p.Id) AS TotalPosts,
        SUM(p.Score) AS TotalPostScore,
        AVG(p.ViewCount) AS AvgViews,
        STRING_AGG(DISTINCT p.Tags, '; ') AS UniqueTags
    FROM Posts p
    JOIN ActiveUsers u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
    AND p.CreationDate BETWEEN '2015-01-01' AND '2023-12-31'
    GROUP BY p.OwnerUserId
    HAVING COUNT(p.Id) > 50
),
UserComments AS (
    SELECT 
        c.UserId,
        COUNT(c.Id) AS TotalComments,
        SUM(c.Score) AS TotalCommentScore
    FROM Comments c
    JOIN ActiveUsers u ON c.UserId = u.Id
    WHERE c.CreationDate BETWEEN '2018-01-01' AND '2023-12-31'
    GROUP BY c.UserId
),
UserVotes AS (
    SELECT 
        v.UserId,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpvotesGiven,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownvotesGiven,
        SUM(v.BountyAmount) AS TotalBountySpent
    FROM Votes v
    JOIN ActiveUsers u ON v.UserId = u.Id
    WHERE v.CreationDate BETWEEN '2020-01-01' AND '2023-12-31'
    GROUP BY v.UserId
),
UserBadges AS (
    SELECT 
        b.UserId,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM Badges b
    JOIN ActiveUsers u ON b.UserId = u.Id
    WHERE b.Date BETWEEN '2015-01-01' AND '2023-12-31'
    GROUP BY b.UserId
)
SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    COALESCE(p.TotalPosts, 0) AS TotalPosts,
    COALESCE(p.TotalPostScore, 0) AS TotalPostScore,
    COALESCE(c.TotalComments, 0) AS TotalComments,
    COALESCE(v.UpvotesGiven, 0) AS UpvotesGiven,
    COALESCE(v.DownvotesGiven, 0) AS DownvotesGiven,
    COALESCE(b.GoldBadges, 0) + COALESCE(b.SilverBadges, 0) * 0.5 + COALESCE(b.BronzeBadges, 0) * 0.25 AS BadgeScore,
    (COALESCE(p.TotalPostScore, 0) * 0.6 + COALESCE(c.TotalCommentScore, 0) * 0.3 + COALESCE(v.TotalBountySpent, 0) * 0.1) AS EngagementScore
FROM ActiveUsers u
LEFT JOIN UserPosts p ON u.Id = p.OwnerUserId
LEFT JOIN UserComments c ON u.Id = c.UserId
LEFT JOIN UserVotes v ON u.Id = v.UserId
LEFT JOIN UserBadges b ON u.Id = b.UserId
ORDER BY EngagementScore DESC, BadgeScore DESC
LIMIT 100;

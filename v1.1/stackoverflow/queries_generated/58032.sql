-- {"query": "58032.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 1195} 

WITH HighRepUsers AS (
    SELECT Id, DisplayName, Reputation
    FROM Users
    WHERE Reputation > 100000
), UserPosts AS (
    SELECT 
        p.OwnerUserId, 
        p.Id AS PostId, 
        p.Title, 
        p.Score, 
        p.Tags,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS Upvotes
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.OwnerUserId IN (SELECT Id FROM HighRepUsers)
), TagStats AS (
    SELECT 
        up.OwnerUserId,
        TRIM('"' FROM tag) AS TagName,
        COUNT(*) AS TagUsage,
        AVG(up.Score) OVER (PARTITION BY TRIM('"' FROM tag)) AS AvgTagScore
    FROM UserPosts up
    CROSS JOIN LATERAL STRING_TO_ARRAY(REPLACE(up.Tags, '><', ','), ',') AS tags(tag)
    WHERE up.Tags IS NOT NULL
), UserBadges AS (
    SELECT 
        UserId,
        COUNT(*) FILTER (WHERE Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE Class = 2) AS SilverBadges
    FROM Badges
    WHERE UserId IN (SELECT Id FROM HighRepUsers)
    GROUP BY UserId
)
SELECT 
    hru.DisplayName,
    hru.Reputation,
    COUNT(DISTINCT up.PostId) AS TotalQuestions,
    SUM(up.CommentCount) AS TotalComments,
    SUM(up.Upvotes) AS TotalUpvotes,
    MAX(ub.GoldBadges) AS GoldBadges,
    STRING_AGG(DISTINCT ts.TagName, ', ' ORDER BY ts.TagUsage DESC LIMIT 5) AS TopTags,
    AVG(up.Score) AS AvgPostScore,
    MAX((SELECT SUM(BountyAmount) FROM Votes WHERE VoteTypeId = 8 AND UserId = hru.Id)) AS TotalBounty
FROM HighRepUsers hru
JOIN UserPosts up ON hru.Id = up.OwnerUserId
JOIN UserBadges ub ON hru.Id = ub.UserId
LEFT JOIN TagStats ts ON hru.Id = ts.OwnerUserId
GROUP BY hru.Id, hru.DisplayName, hru.Reputation
HAVING COUNT(DISTINCT up.PostId) > 50 AND SUM(up.Upvotes) > 1000
ORDER BY 
    hru.Reputation DESC, 
    TotalQuestions DESC, 
    TotalUpvotes DESC
LIMIT 100;

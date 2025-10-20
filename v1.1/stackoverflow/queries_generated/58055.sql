-- {"query": "58055.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 1221} 

WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS TotalQuestions,
        (SELECT AVG(p.Score) FROM Posts p WHERE p.OwnerUserId = u.Id) AS AvgPostScore,
        (SELECT SUM(p.ViewCount) FROM Posts p WHERE p.OwnerUserId = u.Id) AS TotalViews,
        (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id) AS TotalComments,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2) AS TotalUpvotesGiven,
        (SELECT COUNT(*) FROM Votes v2 WHERE v2.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id) AND v2.VoteTypeId = 2) AS TotalUpvotesReceived,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges
    FROM Users u
)
SELECT 
    us.UserId,
    u.DisplayName,
    us.Reputation,
    us.TotalQuestions,
    us.AvgPostScore,
    us.TotalViews,
    us.TotalComments,
    us.TotalUpvotesGiven,
    us.TotalUpvotesReceived,
    ph.EditCount,
    (SELECT STRING_AGG(TagName, ', ' ORDER BY Count DESC) FROM Tags t WHERE t.Id IN (SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) FROM Posts p WHERE p.OwnerUserId = us.UserId AND p.PostTypeId = 1 LIMIT 5)) AS TopTags,
    RANK() OVER (ORDER BY us.Reputation DESC) AS GlobalRank,
    RANK() OVER (PARTITION BY CASE WHEN us.GoldBadges > 0 THEN 'Gold' ELSE 'NoGold' END ORDER BY us.Reputation DESC) AS CategoryRank
FROM UserStats us
JOIN Users u ON us.UserId = u.Id
LEFT JOIN (
    SELECT 
        UserId,
        COUNT(*) AS EditCount 
    FROM PostHistory 
    WHERE PostHistoryTypeId IN (2,5,8) 
    GROUP BY UserId
) ph ON ph.UserId = us.UserId
WHERE us.TotalQuestions > 10
HAVING us.AvgPostScore > 5 OR TotalUpvotesReceived > 100
ORDER BY 
    us.Reputation DESC, 
    TotalViews DESC, 
    TotalUpvotesReceived DESC
LIMIT 100;

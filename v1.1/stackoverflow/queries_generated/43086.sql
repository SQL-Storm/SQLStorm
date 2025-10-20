-- {"query": "43086.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 511} 

WITH UserBadgesCount AS (
    SELECT UserId, COUNT(*) AS TotalBadges, SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
),
TopQuestions AS (
    SELECT p.Id, p.OwnerUserId, p.Title, p.Score, p.ViewCount, p.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Score > 10
),
UserPostsAggregate AS (
    SELECT u.Id AS UserId, COUNT(DISTINCT p.Id) AS TotalPosts, COUNT(DISTINCT c.Id) AS TotalComments,
        SUM(p.Score) AS TotalScore, AVG(p.ViewCount) AS AvgViewCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id
)
SELECT 
    u.DisplayName, 
    u.Reputation, 
    ub.TotalBadges, 
    ub.GoldBadges, 
    ub.SilverBadges, 
    ub.BronzeBadges,
    up.TotalPosts, 
    up.TotalComments, 
    up.TotalScore, 
    up.AvgViewCount,
    tq.Title AS TopQuestionTitle, 
    tq.Score AS TopQuestionScore
FROM Users u
INNER JOIN UserBadgesCount ub ON u.Id = ub.UserId
INNER JOIN UserPostsAggregate up ON u.Id = up.UserId
LEFT JOIN TopQuestions tq ON u.Id = tq.OwnerUserId AND tq.rn = 1
WHERE u.Reputation > 1000
ORDER BY u.Reputation DESC, ub.TotalBadges DESC
LIMIT 50;

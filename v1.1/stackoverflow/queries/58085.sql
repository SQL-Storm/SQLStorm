-- {"query": "58085.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 1188} 
WITH ActiveUsers AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        u.Reputation, 
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT v.Id) AS TotalVotes,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.CreationDate BETWEEN '2020-01-01' AND '2023-12-31' AND p.Score > 10
    LEFT JOIN Comments c ON u.Id = c.UserId AND c.CreationDate BETWEEN '2020-01-01' AND '2023-12-31'
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2, 8)
    LEFT JOIN Badges b ON u.Id = b.UserId AND b.Class IN (1, 2, 3)
    WHERE u.Reputation > 10000
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(p.Id) > 50 OR COUNT(c.Id) > 100
),
PostStats AS (
    SELECT 
        OwnerUserId,
        AVG(AnswerCount) AS AvgAnswersPerQuestion,
        MAX(Score) AS HighestPostScore,
        SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersGiven
    FROM Posts
    WHERE OwnerUserId IN (SELECT Id FROM ActiveUsers)
    GROUP BY OwnerUserId
),
BadgeClassRanking AS (
    SELECT 
        UserId,
        MAX(CASE WHEN Class = 1 THEN Name END) AS TopGoldBadge,
        MAX(CASE WHEN Class = 2 THEN Name END) AS TopSilverBadge,
        MAX(CASE WHEN Class = 3 THEN Name END) AS TopBronzeBadge,
        DENSE_RANK() OVER (PARTITION BY Class ORDER BY COUNT(Id) DESC) AS BadgeClassRank
    FROM Badges
    WHERE UserId IN (SELECT Id FROM ActiveUsers)
    GROUP BY UserId, Class
)
SELECT 
    au.Id,
    au.DisplayName,
    au.Reputation,
    au.TotalPosts,
    au.TotalComments,
    au.TotalVotes,
    au.TotalBadges,
    ps.AvgAnswersPerQuestion,
    ps.HighestPostScore,
    ps.QuestionsAsked,
    ps.AnswersGiven,
    bcr.TopGoldBadge,
    bcr.TopSilverBadge,
    bcr.TopBronzeBadge,
    (au.TotalPosts * 5 + au.TotalComments * 2 + au.TotalVotes * 3) AS ContributionScore,
    au.ReputationRank
FROM ActiveUsers au
JOIN PostStats ps ON au.Id = ps.OwnerUserId
LEFT JOIN BadgeClassRanking bcr ON au.Id = bcr.UserId
ORDER BY ContributionScore DESC, ReputationRank ASC
LIMIT 100;
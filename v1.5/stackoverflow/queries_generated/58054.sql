-- {"query": "58054.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 1410} 

WITH ActiveUsers AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        u.Reputation, 
        u.CreationDate,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId IN (1, 2)) AS TotalPosts,
        (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id) AS TotalComments,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2) AS TotalUpvotesGiven,
        (SELECT SUM(v.BountyAmount) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 8) AS TotalBountySpent
    FROM Users u
    WHERE u.Reputation > 1000
),
PostStats AS (
    SELECT 
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS QuestionsAsked,
        COUNT(DISTINCT a.Id) AS AnswersProvided,
        AVG(p.Score) AS AvgQuestionScore,
        MAX(p.ViewCount) AS MaxViewsOnQuestion,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesReceived
    FROM Posts p
    LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
    LEFT JOIN Votes v ON v.PostId = p.Id
    WHERE p.PostTypeId = 1 AND p.CreationDate > '2020-01-01'
    GROUP BY p.OwnerUserId
),
BadgeAchievers AS (
    SELECT 
        b.UserId,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Name END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Name END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Name END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
    HAVING COUNT(*) > 5
)
SELECT 
    au.Id,
    au.DisplayName,
    au.Reputation,
    au.TotalPosts,
    au.TotalComments,
    au.TotalUpvotesGiven,
    au.TotalBountySpent,
    ps.QuestionsAsked,
    ps.AnswersProvided,
    ps.AvgQuestionScore,
    ps.MaxViewsOnQuestion,
    ps.TotalUpvotesReceived,
    ba.GoldBadges,
    ba.SilverBadges,
    ba.BronzeBadges,
    DENSE_RANK() OVER (ORDER BY (ps.TotalUpvotesReceived + au.TotalUpvotesGiven) DESC) AS CommunityImpactRank
FROM ActiveUsers au
JOIN PostStats ps ON au.Id = ps.OwnerUserId
JOIN BadgeAchievers ba ON au.Id = ba.UserId
WHERE au.TotalPosts > 10
ORDER BY 
    CommunityImpactRank,
    au.Reputation DESC,
    ps.TotalUpvotesReceived DESC
LIMIT 100;

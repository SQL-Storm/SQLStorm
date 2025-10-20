-- {"query": "58096.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 1509} 

WITH ActiveUsers AS (
    SELECT 
        u.Id, 
        u.Reputation, 
        u.DisplayName, 
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= CURRENT_DATE - INTERVAL '5 years'
    GROUP BY u.Id, u.Reputation, u.DisplayName
    HAVING COUNT(b.Id) > 0
), PostStats AS (
    SELECT 
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersProvided,
        AVG(p.Score) AS AvgPostScore,
        SUM(p.ViewCount) AS TotalViews,
        COUNT(DISTINCT ph.Id) AS PostEdits,
        COUNT(DISTINCT pl.RelatedPostId) AS LinkedPosts
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId BETWEEN 4 AND 6
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId AND pl.LinkTypeId = 1
    WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
    GROUP BY p.OwnerUserId
), VoteAnalysis AS (
    SELECT 
        v.UserId,
        COUNT(DISTINCT v.Id) AS TotalVotes,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
        SUM(v.BountyAmount) AS TotalBountyAwarded
    FROM Votes v
    WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '3 years'
    GROUP BY v.UserId
)
SELECT 
    au.DisplayName,
    au.Reputation,
    au.TotalBadges,
    au.GoldBadges,
    au.SilverBadges,
    au.BronzeBadges,
    ps.TotalPosts,
    ps.QuestionsAsked,
    ps.AnswersProvided,
    ps.AvgPostScore,
    ps.TotalViews,
    ps.PostEdits,
    ps.LinkedPosts,
    va.TotalVotes,
    va.Upvotes,
    va.Downvotes,
    va.TotalBountyAwarded,
    RANK() OVER (ORDER BY au.Reputation DESC) AS ReputationRank,
    DENSE_RANK() OVER (ORDER BY ps.TotalPosts DESC) AS PostCountRank,
    NTILE(10) OVER (ORDER BY va.TotalVotes DESC) AS VoteDecile
FROM ActiveUsers au
JOIN PostStats ps ON au.Id = ps.OwnerUserId
LEFT JOIN VoteAnalysis va ON au.Id = va.UserId
WHERE ps.TotalPosts > 50 AND va.TotalVotes > 100
ORDER BY 
    au.Reputation DESC, 
    ps.TotalPosts DESC, 
    va.TotalVotes DESC
LIMIT 100;

-- {"query": "20090.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1538} 

WITH UserBadgeStats AS (
    -- CTE 1: Aggregate badge counts for each user to identify achievements.
    SELECT
        UserId,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges
    FROM Badges
    WHERE UserId IS NOT NULL
    GROUP BY UserId
),
UserPostInteraction AS (
    -- CTE 2: Analyze user's posts and their temporal relationship using window functions.
    SELECT
        p.Id,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.CreationDate,
        p.Tags,
        p.ViewCount,
        p.FavoriteCount,
        p.AnswerCount,
        p.CommentCount,
        LAG(p.CreationDate, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostDate,
        LEAD(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextPostScore,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) as RankByScore
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL AND p.CreationDate > '2020-01-01' AND p.CommunityOwnedDate IS NULL
),
AggregatedUserStats AS (
    -- CTE 3: Consolidate user statistics from posts and interactions.
    SELECT
        upi.OwnerUserId,
        COUNT(upi.Id) AS TotalPosts,
        SUM(CASE WHEN upi.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN upi.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(upi.Score) AS TotalScore,
        AVG(upi.Score) AS AverageScore,
        SUM(COALESCE(upi.ViewCount, 0)) AS TotalViewsOnQuestions,
        AVG(EXTRACT(EPOCH FROM (upi.CreationDate - upi.PreviousPostDate))) AS AvgSecondsBetweenPosts,
        CORR(upi.Score, upi.NextPostScore) AS ScoreCorrelationWithNext,
        STRING_AGG(CASE WHEN upi.RankByScore <= 3 THEN upi.Tags END, ',') AS TopPostTags
    FROM UserPostInteraction upi
    WHERE upi.PreviousPostDate IS NOT NULL
    GROUP BY upi.OwnerUserId
    HAVING COUNT(upi.Id) > 10
)
-- Final SELECT: Combine all metrics to create a comprehensive user performance report.
-- This part joins users with their aggregated stats, badge counts, and performs complex calculations and subqueries.
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    aus.TotalPosts,
    aus.QuestionCount,
    aus.AnswerCount,
    CAST(aus.AverageScore AS DECIMAL(18, 2)) AS AvgScore,
    -- Correlated subquery to find the number of comments made by the user on posts they do not own.
    (SELECT COUNT(c.Id) FROM Comments c WHERE c.UserId = u.Id AND c.PostId NOT IN (SELECT p.Id FROM Posts p WHERE p.OwnerUserId = u.Id)) AS ExternalComments,
    ubs.GoldBadges,
    ubs.SilverBadges,
    -- Complex CASE expression to categorize users based on their activity profile.
    CASE
        WHEN aus.QuestionCount > aus.AnswerCount * 2 AND u.Reputation > 10000 THEN 'Prolific Questioner'
        WHEN aus.AnswerCount > aus.QuestionCount * 2 AND u.Reputation > 10000 THEN 'Dedicated Answerer'
        WHEN ubs.GoldBadges > 5 THEN 'Decorated Veteran'
        ELSE 'General Contributor'
    END AS UserCategory,
    -- String manipulation and NULL handling to create a summary.
    CONCAT('Avg time between posts: ', CAST(FLOOR(aus.AvgSecondsBetweenPosts / 3600) AS VARCHAR), 'h ',
           CAST(FLOOR(MOD(aus.AvgSecondsBetweenPosts, 3600) / 60) AS VARCHAR), 'm. Top tags: ',
           COALESCE(SUBSTRING(aus.TopPostTags FROM 1 FOR 100), 'N/A')) AS ActivitySummary,
    -- Calculation involving multiple fields to create a composite 'influence' score.
    (u.Reputation * 0.4 + aus.TotalScore * 0.3 + aus.TotalViewsOnQuestions * 0.1 + (ubs.GoldBadges * 1000 + ubs.SilverBadges * 100) * 0.2) AS InfluenceScore,
    pa.HighestScoringPostDate
FROM
    Users u
INNER JOIN
    AggregatedUserStats aus ON u.Id = aus.OwnerUserId
LEFT OUTER JOIN
    UserBadgeStats ubs ON u.Id = ubs.UserId
-- Subquery in a JOIN clause to find the creation date of each user's highest-scoring post.
LEFT OUTER JOIN
    (
        SELECT OwnerUserId, CreationDate AS HighestScoringPostDate
        FROM UserPostInteraction
        WHERE RankByScore = 1
    ) pa ON u.Id = pa.OwnerUserId
WHERE
    u.Reputation > 20000
    AND u.LastAccessDate > (CURRENT_TIMESTAMP - INTERVAL '1 year')
    AND aus.AvgSecondsBetweenPosts IS NOT NULL
    AND aus.ScoreCorrelationWithNext BETWEEN -1 AND 1
UNION ALL
-- Set operator to include a different class of users: those who have started bounties on highly-viewed questions.
SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    0, 0, 0, 0.00, 0, 0, 0,
    'Bounty Sponsor' AS UserCategory,
    'User has offered bounties on popular questions.' AS ActivitySummary,
    u.Reputation * 0.8 AS InfluenceScore,
    NULL
FROM Users u
WHERE u.Id IN (
    SELECT DISTINCT v.UserId
    FROM Votes v
    JOIN Posts p ON v.PostId = p.Id
    WHERE v.VoteTypeId = 8 -- BountyStart
      AND v.UserId IS NOT NULL
      AND p.ViewCount > 100000
) AND u.Reputation < 20000 -- Look for non-power users doing this
ORDER BY
    UserCategory, InfluenceScore DESC
LIMIT 200;

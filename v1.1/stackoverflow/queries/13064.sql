-- {"query": "13064.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2142, "output_tokens": 543} 
WITH UserBadges AS (
    SELECT 
        UserId,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
),
HighScoreQuestions AS (
    SELECT 
        Id,
        OwnerUserId,
        Title,
        Score,
        DENSE_RANK() OVER (PARTITION BY OwnerUserId ORDER BY Score DESC) AS Rank
    FROM Posts
    WHERE PostTypeId = 1 AND OwnerUserId IS NOT NULL
),
TopQuestionsPerUser AS (
    SELECT 
        q.OwnerUserId,
        q.Title,
        q.Score
    FROM HighScoreQuestions q
    WHERE q.Rank <= 3
),
CommentsAnalysis AS (
    SELECT
        UserId,
        COUNT(*) AS TotalComments,
        SUM(LENGTH(COALESCE(Text, ''))) AS TotalCommentLength
    FROM Comments
    GROUP BY UserId
)
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    SUM(COALESCE(tp.Score, 0)) AS TopQuestionsScore,
    ca.TotalComments,
    ca.TotalCommentLength,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, SUM(COALESCE(tp.Score, 0)) DESC) AS UserRank
FROM Users u
LEFT JOIN UserBadges ub ON u.Id = ub.UserId
LEFT JOIN TopQuestionsPerUser tp ON u.Id = tp.OwnerUserId
LEFT JOIN CommentsAnalysis ca ON u.Id = ca.UserId
WHERE u.LastAccessDate > cast('2024-10-01' as date) - INTERVAL '1 year'
GROUP BY 
    u.Id,
    u.DisplayName,
    u.Reputation,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ca.TotalComments,
    ca.TotalCommentLength
HAVING SUM(COALESCE(tp.Score, 0)) > 100
ORDER BY UserRank;
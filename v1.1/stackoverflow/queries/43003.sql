-- {"query": "43003.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 556} 
WITH UserActivity AS (
    SELECT 
        OwnerUserId,
        COUNT(DISTINCT CASE WHEN PostTypeId = 1 THEN Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN PostTypeId = 2 THEN Id END) AS AnswersProvided,
        AVG(Score) AS AvgScore,
        MAX(LastEditDate) AS LastActivityDate
    FROM Posts
    WHERE OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
),
HighlyActiveUsers AS (
    SELECT 
        U.Id,
        U.DisplayName,
        U.Reputation,
        UA.QuestionsAsked,
        UA.AnswersProvided,
        UA.AvgScore
    FROM Users U
    JOIN UserActivity UA ON U.Id = UA.OwnerUserId
    WHERE UA.QuestionsAsked > 10
      AND UA.AnswersProvided > 50
      AND UA.AvgScore > 15
),
TopBadges AS (
    SELECT 
        UserId,
        COUNT(*) FILTER (WHERE Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE Class = 3) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
),
UserPerformance AS (
    SELECT 
        HAU.Id,
        HAU.DisplayName,
        HAU.Reputation,
        COALESCE(TB.GoldBadges, 0) AS GoldBadges,
        COALESCE(TB.SilverBadges, 0) AS SilverBadges,
        COALESCE(TB.BronzeBadges, 0) AS BronzeBadges,
        HAU.QuestionsAsked,
        HAU.AnswersProvided,
        HAU.AvgScore
    FROM HighlyActiveUsers HAU
    LEFT JOIN TopBadges TB ON HAU.Id = TB.UserId
)
SELECT 
    UP.Id,
    UP.DisplayName,
    UP.Reputation,
    UP.GoldBadges,
    UP.SilverBadges,
    UP.BronzeBadges,
    UP.QuestionsAsked,
    UP.AnswersProvided,
    UP.AvgScore,
    DENSE_RANK() OVER (ORDER BY UP.Reputation DESC, UP.GoldBadges DESC) AS PerformanceRank
FROM UserPerformance UP
ORDER BY PerformanceRank
LIMIT 100;
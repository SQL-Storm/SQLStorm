-- {"query": "1041.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 560} 

WITH UserPostStats AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        COUNT(P.Id) AS TotalPosts,
        AVG(P.Score) AS AvgPostScore,
        SUM(P.ViewCount) AS TotalViews,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    GROUP BY U.Id, U.DisplayName
),
TopUsersWithBadges AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        COUNT(B.Id) AS BadgeCount
    FROM Users U
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName
),
CombinedStats AS (
    SELECT 
        UPS.UserId,
        UPS.DisplayName,
        UPS.TotalPosts,
        UPS.AvgPostScore,
        UPS.TotalViews,
        UPS.QuestionCount,
        UPS.AnswerCount,
        TUB.BadgeCount
    FROM UserPostStats UPS
    JOIN TopUsersWithBadges TUB ON UPS.UserId = TUB.UserId
)
SELECT 
    CS.UserId,
    CS.DisplayName,
    COALESCE(CS.TotalPosts, 0) AS TotalPosts,
    COALESCE(CS.AvgPostScore, 0) AS AvgPostScore,
    COALESCE(CS.TotalViews, 0) AS TotalViews,
    COALESCE(CS.QuestionCount, 0) AS QuestionCount,
    COALESCE(CS.AnswerCount, 0) AS AnswerCount,
    COALESCE(CS.BadgeCount, 0) AS BadgeCount,
    RANK() OVER (ORDER BY COALESCE(CS.TotalViews, 0) DESC) AS ViewRank,
    RANK() OVER (ORDER BY COALESCE(CS.AvgPostScore, 0) DESC) AS ScoreRank
FROM CombinedStats CS
WHERE CS.BadgeCount >= 5
UNION ALL
SELECT 
    U.Id AS UserId,
    U.DisplayName,
    0 AS TotalPosts,
    0 AS AvgPostScore,
    0 AS TotalViews,
    0 AS QuestionCount,
    0 AS AnswerCount,
    0 AS BadgeCount,
    RANK() OVER (ORDER BY U.Reputation DESC) AS ViewRank,
    NULL AS ScoreRank
FROM Users U
WHERE U.Id NOT IN (SELECT UserId FROM CombinedStats)
ORDER BY ViewRank, ScoreRank;

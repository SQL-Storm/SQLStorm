WITH UserBadgeCounts AS (
    SELECT 
        UserId,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
),
PostActivity AS (
    SELECT 
        p.OwnerUserId,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersProvided,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) AS TotalQuestionViews,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE NULL END) AS AvgAnswersPerQuestion
    FROM Posts p
    WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
    GROUP BY p.OwnerUserId
),
TopQuestions AS (
    SELECT 
        p.OwnerUserId,
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        ROW_NUMBER() OVER (
            PARTITION BY p.OwnerUserId
            ORDER BY p.Score DESC, p.ViewCount DESC
        ) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL
)
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COALESCE(ubc.GoldBadges, 0) AS GoldBadges,
    COALESCE(ubc.SilverBadges, 0) AS SilverBadges,
    COALESCE(ubc.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(pa.QuestionsAsked, 0) AS QuestionsAsked,
    COALESCE(pa.AnswersProvided, 0) AS AnswersProvided,
    COALESCE(pa.TotalQuestionViews, 0) AS TotalQuestionViews,
    COALESCE(pa.AvgAnswersPerQuestion, 0) AS AvgAnswersPerQuestion,
    tq.Title AS TopQuestionTitle,
    tq.Score AS TopQuestionScore
FROM Users u
LEFT JOIN UserBadgeCounts ubc ON u.Id = ubc.UserId
LEFT JOIN PostActivity pa ON u.Id = pa.OwnerUserId
LEFT JOIN TopQuestions tq ON u.Id = tq.OwnerUserId AND tq.rn = 1
WHERE u.Reputation > 1000
GROUP BY 
    u.Id, u.DisplayName, u.Reputation,
    ubc.GoldBadges, ubc.SilverBadges, ubc.BronzeBadges,
    pa.QuestionsAsked, pa.AnswersProvided, pa.TotalQuestionViews, pa.AvgAnswersPerQuestion,
    tq.Title, tq.Score
ORDER BY u.Reputation DESC, ubc.GoldBadges DESC, ubc.SilverBadges DESC, ubc.BronzeBadges DESC;
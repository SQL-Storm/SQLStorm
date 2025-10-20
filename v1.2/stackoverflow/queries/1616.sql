WITH UserBadgeCounts AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadgeCount,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadgeCount,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadgeCount,
        RANK() OVER (ORDER BY COUNT(b.Id) DESC) AS TotalBadgeRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName
),
QuestionStats AS (
    SELECT
        p.OwnerUserId,
        COUNT(p.Id) AS NumQuestions,
        AVG(p.Score) AS AvgQuestionScore,
        SUM(p.ViewCount) AS TotalQuestionViews,
        MAX(p.CreationDate) AS LatestQuestion
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
AnswerStats AS (
    SELECT
        p.OwnerUserId,
        COUNT(p.Id) AS NumAnswers,
        AVG(p.Score) AS AvgAnswerScore,
        SUM(p.CommentCount) AS TotalAnswerComments,
        MAX(p.CreationDate) AS LatestAnswer
    FROM Posts p
    WHERE p.PostTypeId = 2
      AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
)
SELECT
    ubc.UserId,
    ubc.DisplayName,
    ubc.GoldBadgeCount,
    ubc.SilverBadgeCount,
    ubc.BronzeBadgeCount,
    ubc.TotalBadgeRank,
    qs.NumQuestions,
    qs.AvgQuestionScore,
    qs.TotalQuestionViews,
    qs.LatestQuestion,
    ans.NumAnswers,
    ans.AvgAnswerScore,
    ans.TotalAnswerComments,
    ans.LatestAnswer
FROM UserBadgeCounts ubc
LEFT JOIN QuestionStats qs ON ubc.UserId = qs.OwnerUserId
LEFT JOIN AnswerStats ans ON ubc.UserId = ans.OwnerUserId;
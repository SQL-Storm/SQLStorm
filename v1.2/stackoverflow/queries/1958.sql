WITH UserQuestionStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS TotalQuestions,
        COUNT(DISTINCT p.AcceptedAnswerId) FILTER (WHERE p.AcceptedAnswerId IS NOT NULL) AS QuestionsWithAcceptedAnswer,
        AVG(CAST(p.Score AS DECIMAL)) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
        SUM(p.ViewCount) FILTER (WHERE p.PostTypeId = 1) AS TotalQuestionViews
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName
)
SELECT *
FROM UserQuestionStats;
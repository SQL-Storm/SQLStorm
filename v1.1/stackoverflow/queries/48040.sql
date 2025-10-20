-- {"query": "48040.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 506} 
WITH RankedPosts AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn
    FROM Posts p
    WHERE p.PostTypeId = 1 -- Questions only
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT rp.Id) AS QuestionCount,
        SUM(rp.Score) AS TotalQuestionScore,
        AVG(rp.Score) AS AverageQuestionScore,
        SUM(rp.ViewCount) AS TotalQuestionViews,
        AVG(rp.ViewCount) AS AverageQuestionViews,
        SUM(rp.AnswerCount) AS TotalAnswersReceived,
        AVG(rp.AnswerCount) AS AverageAnswersReceived,
        SUM(rp.CommentCount) AS TotalCommentsReceived,
        AVG(rp.CommentCount) AS AverageCommentsReceived,
        MAX(rp.CreationDate) AS LastQuestionDate
    FROM Users u
    JOIN RankedPosts rp ON u.Id = rp.OwnerUserId
    WHERE rp.rn <= 100 -- Consider the 100 most recent questions for each user
    GROUP BY u.Id, u.DisplayName
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.QuestionCount,
    ua.TotalQuestionScore,
    ua.AverageQuestionScore,
    ua.TotalQuestionViews,
    ua.AverageQuestionViews,
    ua.TotalAnswersReceived,
    ua.AverageAnswersReceived,
    ua.TotalCommentsReceived,
    ua.AverageCommentsReceived,
    ua.LastQuestionDate,
    CASE
        WHEN ua.TotalQuestionScore > 1000 THEN 'High Performer'
        WHEN ua.TotalQuestionScore > 500 THEN 'Good Performer'
        WHEN ua.TotalQuestionScore > 100 THEN 'Average Performer'
        ELSE 'Developing Performer'
    END AS PerformanceTier
FROM UserActivity ua
ORDER BY ua.TotalQuestionScore DESC, ua.TotalQuestionViews DESC;
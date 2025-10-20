WITH YearlyUserStats AS (
    SELECT
        u.Id AS UserId,
        EXTRACT(YEAR FROM u.CreationDate) AS CreationYear,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionsCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswersCount,
        CAST(SUM(p.Score) AS INTEGER) AS TotalScore
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, EXTRACT(YEAR FROM u.CreationDate)
)
SELECT *
FROM YearlyUserStats;
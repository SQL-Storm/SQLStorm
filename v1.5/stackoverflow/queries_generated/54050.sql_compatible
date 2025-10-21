WITH
question_tags AS (
    SELECT p.Id          AS PostId,
           t.TagName
    FROM Posts p
    CROSS JOIN LATERAL (
        SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '"><')) AS TagName
    ) AS split
    JOIN Tags t ON t.TagName = split.TagName
    WHERE p.PostTypeId = 1
),
first_answers AS (
    SELECT a.ParentId          AS QuestionId,
           MIN(a.CreationDate) AS FirstAnswerDate,
           MAX(a.Score)        AS MaxAnswerScore
    FROM Posts a
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId
)
SELECT u.Id                                        AS UserId,
       u.DisplayName,
       COUNT(DISTINCT q.Id)                       AS QuestionCount,
       SUM(q.Score)                               AS TotalQuestionScore,
       AVG(q.Score)                               AS AvgQuestionScore,
       AVG(CASE WHEN q.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END)
           AS AcceptanceRate,
       AVG(EXTRACT(EPOCH FROM (fa.FirstAnswerDate - q.CreationDate)) / 3600.0) AS AvgHoursToFirstAnswer,
       MAX(fa.MaxAnswerScore)                    AS MaxAnswerScore,
       COUNT(DISTINCT qt.TagName)                AS UniqueTagsUsed,
       RANK() OVER (ORDER BY SUM(q.Score) DESC)   AS Rank
FROM Users u
JOIN Posts q ON q.OwnerUserId = u.Id
             AND q.PostTypeId = 1
LEFT JOIN first_answers fa ON fa.QuestionId = q.Id
LEFT JOIN question_tags qt ON qt.PostId = q.Id
GROUP BY u.Id, u.DisplayName
ORDER BY Rank;
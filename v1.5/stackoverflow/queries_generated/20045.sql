-- {"query": "20045.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1664} 

WITH RelevantQuestions AS (
    -- CTE 1: Select a subset of challenging questions that have accepted answers and are not closed.
    -- This narrows down the scope to posts where quality and speed can be measured.
    SELECT
        p.Id,
        p.AcceptedAnswerId,
        p.CreationDate AS QuestionCreationDate,
        p.OwnerUserId AS QuestionOwnerId,
        p.Score AS QuestionScore,
        p.Tags
    FROM Posts p
    WHERE p.PostTypeId = 1 -- Question
      AND p.Score > 10
      AND p.AnswerCount >= 2
      AND p.FavoriteCount > 5
      AND p.AcceptedAnswerId IS NOT NULL
      AND p.ClosedDate IS NULL
      AND p.CreationDate BETWEEN '2020-01-01' AND '2023-12-31'
      AND (p.Tags LIKE '%<sql>%' OR p.Tags LIKE '%<database>%' OR p.Tags LIKE '%<performance>%')
),
AnswerMetrics AS (
    -- CTE 2: Gather all answers for the selected questions and calculate performance metrics like time-to-answer.
    -- It also joins with the Users table to get answerer's reputation at the time of answering.
    SELECT
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.OwnerUserId AS AnswererId,
        a.CreationDate AS AnswerCreationDate,
        a.Score AS AnswerScore,
        q.QuestionCreationDate,
        q.AcceptedAnswerId,
        u.DisplayName AS AnswererDisplayName,
        u.Reputation AS AnswererReputation,
        EXTRACT(EPOCH FROM (a.CreationDate - q.QuestionCreationDate)) / 3600.0 AS HoursToAnswer
    FROM Posts a
    JOIN RelevantQuestions q ON a.ParentId = q.Id
    JOIN Users u ON a.OwnerUserId = u.Id
    WHERE a.PostTypeId = 2 -- Answer
      AND a.OwnerUserId IS NOT NULL
),
RankedAnswers AS (
    -- CTE 3: Use window functions to rank answers for each question and calculate user-specific rolling metrics.
    -- This helps identify the first answer, the accepted answer, and a user's performance over time.
    SELECT
        am.*,
        CASE WHEN am.AnswerId = am.AcceptedAnswerId THEN true ELSE false END AS IsAcceptedAnswer,
        ROW_NUMBER() OVER(PARTITION BY am.QuestionId ORDER BY am.AnswerCreationDate ASC) AS AnswerRank,
        LAG(am.AnswerCreationDate, 1) OVER(PARTITION BY am.AnswererId ORDER BY am.AnswerCreationDate) AS PreviousAnswerDate,
        SUM(am.AnswerScore) OVER(PARTITION BY am.AnswererId ORDER BY am.AnswerCreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeScore,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = am.AnswerId AND c.Score > 0) AS PositiveCommentCount
    FROM AnswerMetrics am
),
UserPerformanceSummary AS (
    -- CTE 4: Aggregate the ranked answer data to create a performance summary for each user.
    -- This creates features like acceptance rate, average answer speed, and consistency.
    SELECT
        AnswererId,
        AnswererDisplayName,
        MAX(AnswererReputation) AS CurrentReputation,
        COUNT(*) AS TotalAnswers,
        SUM(CASE WHEN IsAcceptedAnswer THEN 1 ELSE 0 END) AS AcceptedAnswers,
        CAST(SUM(CASE WHEN IsAcceptedAnswer THEN 1 ELSE 0 END) AS DECIMAL) / COUNT(*) AS AcceptanceRate,
        AVG(HoursToAnswer) AS AvgHoursToAnswer,
        SUM(CASE WHEN AnswerRank = 1 THEN 1 ELSE 0 END) AS FirstAnswerCount,
        AVG(AnswerScore) AS AvgAnswerScore,
        STDDEV(AnswerScore) AS StdevAnswerScore,
        SUM(PositiveCommentCount) AS TotalPositiveComments
    FROM RankedAnswers
    GROUP BY AnswererId, AnswererDisplayName
    HAVING COUNT(*) > 5 AND SUM(CASE WHEN IsAcceptedAnswer THEN 1 ELSE 0 END) > 1
)
-- FINAL QUERY: Combine user summaries with badge information, post edit history, and a separate set of "question specialists" using UNION.
-- This part introduces outer joins, correlated subqueries, complex expressions, and set operators.
(SELECT
    ups.AnswererId AS UserId,
    ups.AnswererDisplayName AS DisplayName,
    ups.CurrentReputation AS Reputation,
    'Answer Specialist' AS UserRole,
    ups.AcceptanceRate,
    ups.AvgHoursToAnswer,
    ups.AvgAnswerScore,
    COALESCE(b.GoldBadges, 0) AS GoldBadges,
    (
        SELECT COUNT(DISTINCT ph.PostId)
        FROM PostHistory ph
        WHERE ph.UserId = ups.AnswererId
          AND ph.PostHistoryTypeId IN (5, 8) -- Edit Body, Rollback Body
    ) AS EditedAnswersCount,
    CONCAT(
        'Rep/Answer: ',
        CAST(ups.CurrentReputation / (ups.TotalAnswers + 1) AS VARCHAR),
        ' | First Answer Ratio: ',
        CAST(CAST(ups.FirstAnswerCount AS DECIMAL) / ups.TotalAnswers AS VARCHAR)
    ) AS PerformanceNotes
FROM UserPerformanceSummary ups
LEFT JOIN (
    SELECT
        UserId,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges
    FROM Badges
    GROUP BY UserId
) b ON ups.AnswererId = b.UserId
WHERE
    ups.AcceptanceRate > 0.5
    AND ups.AvgAnswerScore > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 2 AND DeletionDate IS NULL)
    AND ups.CurrentReputation > 20000)

UNION ALL

(SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    'Question Specialist' AS UserRole,
    NULL AS AcceptanceRate,
    NULL AS AvgHoursToAnswer,
    (SELECT AVG(p.Score) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS AvgQuestionScore,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Name = 'Curious') AS CuriousBadges,
    (SELECT COUNT(DISTINCT p.Id) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL) AS ClosedQuestionsCount,
    REPLACE(COALESCE(u.Location, 'Unknown Location'), ',', ';') AS SanitizedLocation
FROM Users u
WHERE u.Id IN (
    SELECT OwnerUserId
    FROM Posts
    WHERE PostTypeId = 1 AND OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
    HAVING COUNT(*) > 50 AND AVG(Score) > 5
) AND NOT EXISTS (
    SELECT 1 FROM UserPerformanceSummary ups WHERE ups.AnswererId = u.Id
)
AND u.Reputation > 10000)

ORDER BY
    Reputation DESC,
    AcceptanceRate DESC NULLS LAST
LIMIT 200;

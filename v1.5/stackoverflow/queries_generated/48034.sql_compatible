WITH RankedAnswers AS (
    SELECT
        p.Id AS AnswerId,
        p.ParentId AS QuestionId,
        p.OwnerUserId,
        p.CreationDate AS AnswerCreationDate,
        p.Score AS AnswerScore,
        ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 2
),
TopQuestions AS (
    SELECT
        q.Id AS QuestionId,
        q.OwnerUserId,
        q.CreationDate AS QuestionCreationDate,
        q.Title AS QuestionTitle,
        q.Tags AS QuestionTags,
        q.Score AS QuestionScore,
        q.AnswerCount,
        q.ViewCount AS QuestionViewCount,
        MAX(ra.AnswerScore) AS MaxAnswerScore,
        SUM(ra.AnswerScore) AS TotalAnswerScore,
        COUNT(ra.AnswerId) AS NumberOfAnswers
    FROM Posts q
    JOIN RankedAnswers ra ON q.Id = ra.QuestionId
    WHERE q.PostTypeId = 1
    GROUP BY
        q.Id,
        q.OwnerUserId,
        q.CreationDate,
        q.Title,
        q.Tags,
        q.Score,
        q.AnswerCount,
        q.ViewCount
    HAVING
        q.AnswerCount >= 5 AND q.Score > 100 AND q.ViewCount > 1000
)
SELECT
    tq.QuestionId,
    tq.QuestionTitle,
    tq.QuestionTags,
    tq.QuestionCreationDate,
    tq.QuestionScore,
    tq.QuestionViewCount,
    tq.NumberOfAnswers,
    tq.MaxAnswerScore,
    tq.TotalAnswerScore,
    u.DisplayName AS QuestionOwnerDisplayName,
    u.Reputation AS QuestionOwnerReputation,
    (
        SELECT STRING_AGG(pht.Comment, ', ')
        FROM PostHistory pht
        WHERE pht.PostId = tq.QuestionId
          AND pht.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20, 33, 34, 35, 36)
    ) AS QuestionHistoryEvents,
    (
        SELECT COUNT(v.Id)
        FROM Votes v
        WHERE v.PostId = tq.QuestionId
          AND v.VoteTypeId IN (2, 3)
    ) AS QuestionVotesCount,
    (
        SELECT STRING_AGG(COALESCE(CAST(ra2.OwnerUserId AS TEXT), CAST(ra2.AnswerScore AS TEXT)), '; ')
        FROM RankedAnswers ra2
        WHERE ra2.QuestionId = tq.QuestionId
          AND ra2.rn <= 3
    ) AS Top3AnswererInfo,
    (
        SELECT COUNT(DISTINCT c.UserId)
        FROM Comments c
        WHERE c.PostId = tq.QuestionId
          AND c.UserId IS NOT NULL
    ) AS DistinctCommentersOnQuestion,
    CASE
        WHEN tq.QuestionScore > 1000 THEN 'HighScore'
        WHEN tq.QuestionViewCount > 10000 THEN 'HighView'
        ELSE 'Moderate'
    END AS QuestionPerformanceCategory
FROM TopQuestions tq
LEFT JOIN Users u ON tq.OwnerUserId = u.Id
ORDER BY tq.QuestionScore DESC, tq.QuestionViewCount DESC
LIMIT 100;
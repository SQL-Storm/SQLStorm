WITH RecursiveCTEAnswers AS (
    SELECT 
        p.Id AS AnswerId,
        p.ParentId AS QuestionId,
        p.Score,
        p.CreationDate,
        u.Reputation AS AnswererReputation,
        ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS RankByScore
    FROM Posts p
    INNER JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 2
),
TopAnswersWithBadges AS (
    SELECT 
        a.AnswerId,
        a.QuestionId,
        a.Score,
        a.CreationDate,
        a.AnswererReputation,
        COALESCE(b.BadgeCnt, 0) AS AnswererBadgeCount,
        LEAD(a.Score) OVER (PARTITION BY a.QuestionId ORDER BY a.Score DESC) AS NextAnswerScoreDiff
    FROM RecursiveCTEAnswers a
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS BadgeCnt 
        FROM Badges 
        GROUP BY UserId
    ) b ON (SELECT OwnerUserId FROM Posts WHERE Id = a.AnswerId) = b.UserId
    WHERE a.RankByScore = 1
),
QuestionScores AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate AS QuestionCreation,
        q.Score AS QuestionScore,
        q.ViewCount,
        u.DisplayName AS AskerName,
        u.Location,
        COALESCE(
            (SELECT AVG(p.Score) 
             FROM Posts p 
             WHERE p.ParentId = q.Id AND p.PostTypeId = 2), 0) AS AvgAnswerScore
    FROM Posts q
    INNER JOIN Users u ON q.OwnerUserId = u.Id
    WHERE q.PostTypeId = 1
)
SELECT
    qs.QuestionId,
    qs.Title,
    qs.QuestionCreation,
    qs.QuestionScore,
    qs.ViewCount,
    qs.AskerName,
    qs.Location,
    qs.AvgAnswerScore,
    ta.AnswerId,
    ta.Score AS TopAnswerScore,
    ta.CreationDate AS TopAnswerCreation,
    ta.AnswererReputation,
    ta.AnswererBadgeCount,
    ta.NextAnswerScoreDiff
FROM QuestionScores qs
LEFT JOIN TopAnswersWithBadges ta ON ta.QuestionId = qs.QuestionId
GROUP BY
    qs.QuestionId,
    qs.Title,
    qs.QuestionCreation,
    qs.QuestionScore,
    qs.ViewCount,
    qs.AskerName,
    qs.Location,
    qs.AvgAnswerScore,
    ta.AnswerId,
    ta.Score,
    ta.CreationDate,
    ta.AnswererReputation,
    ta.AnswererBadgeCount,
    ta.NextAnswerScoreDiff
ORDER BY qs.QuestionCreation DESC;
-- {"query": "4581.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1249} 

WITH RecentQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title AS QuestionTitle,
        p.OwnerUserId,
        p.CreationDate AS QuestionCreationDate,
        p.Score AS QuestionScore,
        p.AnswerCount,
        u.DisplayName AS OwnerDisplayName,
        u.Reputation AS OwnerReputation,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 AND p.CreationDate >= DATE('now', '-30 days')
),
TopAnswers AS (
    SELECT
        a.ParentId AS QuestionId,
        COUNT(a.Id) AS AnswerCount,
        SUM(a.Score) AS TotalAnswerScore,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.Score) AS MaxAnswerScore,
        a.OwnerUserId AS AnswerOwnerUserId,
        u.DisplayName AS AnswerOwnerDisplayName,
        u.Reputation AS AnswerOwnerReputation,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS ans_rn
    FROM Posts a
    LEFT JOIN Users u ON a.OwnerUserId = u.Id
    WHERE a.PostTypeId = 2 AND a.ParentId IN (SELECT Id FROM RecentQuestions)
    GROUP BY a.ParentId, a.OwnerUserId, u.DisplayName, u.Reputation
),
RankedAnswers AS (
    SELECT
        ta.*,
        CASE WHEN ta.AnswerOwnerUserId = rq.OwnerUserId THEN 1 ELSE 0 END AS IsOwnerAnswer
    FROM TopAnswers ta
    JOIN RecentQuestions rq ON ta.QuestionId = rq.QuestionId
),
QuestionActivity AS (
    SELECT
        ph.PostId AS QuestionId,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20, 35, 36) THEN ph.UserId ELSE NULL END) AS ModerationActionCount,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.UserId ELSE NULL END) AS EditCount,
        MAX(ph.CreationDate) AS LastActivityOnPostHistory
    FROM PostHistory ph
    WHERE ph.PostId IN (SELECT Id FROM RecentQuestions)
    GROUP BY ph.PostId
),
AnswererStats AS (
    SELECT
        ra.QuestionId,
        COUNT(DISTINCT ra.AnswerOwnerUserId) AS DistinctAnswerers,
        SUM(ra.IsOwnerAnswer) AS OwnerAnswersCount,
        AVG(ra.AnswerOwnerReputation) AS AvgAnswererReputation,
        SUM(CASE WHEN ra.ans_rn = 1 THEN 1 ELSE 0 END) AS BestAnswerCount
    FROM RankedAnswers ra
    GROUP BY ra.QuestionId
)
SELECT
    rq.QuestionTitle,
    rq.OwnerDisplayName,
    rq.OwnerReputation,
    rq.QuestionScore,
    rq.AnswerCount AS QuestionAnswerCount,
    COALESCE(asa.DistinctAnswerers, 0) AS DistinctAnswerers,
    COALESCE(asa.OwnerAnswersCount, 0) AS OwnerAnswersCount,
    COALESCE(asa.BestAnswerCount, 0) AS NumberOfBestAnswers,
    COALESCE(qa.ModerationActionCount, 0) AS ModerationActions,
    COALESCE(qa.EditCount, 0) AS Edits,
    CASE
        WHEN rq.QuestionScore > 100 AND COALESCE(asa.DistinctAnswerers, 0) > 5 THEN 'High Engagement High Score'
        WHEN rq.QuestionScore <= 0 AND COALESCE(asa.DistinctAnswerers, 0) <= 1 THEN 'Low Engagement Low Score'
        WHEN rq.QuestionCreationDate < DATE('now', '-7 days') AND COALESCE(qa.EditCount, 0) = 0 THEN 'Old Unedited'
        ELSE 'Other'
    END AS QuestionCategory,
    COUNT(c.Id) AS CommentCountOnQuestion,
    SUM(CASE WHEN c.Score > 0 THEN 1 ELSE 0 END) AS PositiveComments,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = rq.QuestionId AND pl.LinkTypeId = 3) AS DuplicateLinks,
    CASE WHEN rq.OwnerUserId IS NULL OR rq.OwnerDisplayName IS NULL THEN 'Community User' ELSE 'Registered User' END AS OwnerStatus
FROM RecentQuestions rq
LEFT JOIN AnswererStats asa ON rq.QuestionId = asa.QuestionId
LEFT JOIN QuestionActivity qa ON rq.QuestionId = qa.QuestionId
LEFT JOIN Comments c ON rq.QuestionId = c.PostId AND c.PostId = c.PostId -- Self-join for comments on the question
GROUP BY
    rq.QuestionTitle,
    rq.OwnerDisplayName,
    rq.OwnerReputation,
    rq.QuestionScore,
    rq.AnswerCount,
    asa.DistinctAnswerers,
    asa.OwnerAnswersCount,
    asa.BestAnswerCount,
    qa.ModerationActionCount,
    qa.EditCount,
    QuestionCategory,
    rq.OwnerUserId,
    rq.QuestionCreationDate
ORDER BY rq.QuestionScore DESC, rq.AnswerCount DESC
LIMIT 100;

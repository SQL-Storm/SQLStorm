-- {"query": "4183.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1041} 
WITH RecentQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title AS QuestionTitle,
        p.OwnerUserId,
        p.CreationDate AS QuestionCreationDate,
        p.Score AS QuestionScore,
        p.AnswerCount,
        p.FavoriteCount,
        p.ViewCount AS QuestionViewCount,
        u.DisplayName AS OwnerDisplayName,
        u.Reputation AS OwnerReputation,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
    AND p.CreationDate >= DATE('now', '-30 days')
),
QuestionAnswerStats AS (
    SELECT
        q.QuestionId,
        COUNT(a.Id) AS AnswerCountOnRecentQuestion,
        AVG(a.Score) AS AvgAnswerScore,
        SUM(CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END) AS IsAcceptedAnswerPresent,
        MAX(a.CreationDate) AS LastAnswerDate
    FROM Posts q
    JOIN Posts a ON q.Id = a.ParentId
    WHERE a.PostTypeId = 2
    GROUP BY q.QuestionId
),
TopAnswers AS (
    SELECT
        a.ParentId AS QuestionId,
        a.Id AS AnswerId,
        a.OwnerUserId AS AnswerOwnerUserId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerCreationDate,
        u.DisplayName AS AnswerOwnerDisplayName,
        u.Reputation AS AnswerOwnerReputation,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS answer_rn
    FROM Posts a
    JOIN Users u ON a.OwnerUserId = u.Id
    WHERE a.PostTypeId = 2
),
CommentActivity AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS CommentCountOnPost,
        SUM(CASE WHEN c.UserId IS NULL THEN 1 ELSE 0 END) AS AnonymousCommentCount,
        AVG(c.Score) AS AvgCommentScore,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    GROUP BY c.PostId
)
SELECT
    rq.QuestionId,
    rq.QuestionTitle,
    rq.OwnerDisplayName,
    rq.OwnerReputation,
    rq.QuestionCreationDate,
    rq.QuestionScore,
    rq.AnswerCount AS TotalAnswersExpected,
    COALESCE(qas.AnswerCountOnRecentQuestion, 0) AS ActualAnswers,
    CASE WHEN qas.IsAcceptedAnswerPresent > 0 THEN 'Yes' ELSE 'No' END AS HasAcceptedAnswer,
    qas.AvgAnswerScore,
    rq.FavoriteCount,
    rq.QuestionViewCount,
    ca.CommentCountOnPost,
    ca.AnonymousCommentCount,
    ca.AvgCommentScore,
    ta.AnswerId AS TopAnswerId,
    ta.AnswerScore AS TopAnswerScore,
    ta.AnswerOwnerDisplayName AS TopAnswerOwner,
    ta.AnswerOwnerReputation AS TopAnswerOwnerReputation,
    CASE
        WHEN DATEDIFF('minute', rq.QuestionCreationDate, COALESCE(qas.LastAnswerDate, rq.LastActivityDate)) < 5 THEN 'Very Fast'
        WHEN DATEDIFF('hour', rq.QuestionCreationDate, COALESCE(qas.LastAnswerDate, rq.LastActivityDate)) < 1 THEN 'Fast'
        WHEN DATEDIFF('day', rq.QuestionCreationDate, COALESCE(qas.LastAnswerDate, rq.LastActivityDate)) < 7 THEN 'Medium'
        ELSE 'Slow'
    END AS AnswerSpeedCategory,
    LENGTH(rq.QuestionTitle) * LENGTH(rq.OwnerDisplayName) AS TitleOwnerNameProduct,
    UPPER(SUBSTR(rq.QuestionTitle, 1, 3)) || '-' || LOWER(SUBSTR(rq.OwnerDisplayName, -3)) AS ProcessedString
FROM RecentQuestions rq
LEFT JOIN QuestionAnswerStats qas ON rq.QuestionId = qas.QuestionId
LEFT JOIN TopAnswers ta ON rq.QuestionId = ta.QuestionId AND ta.answer_rn = 1
LEFT JOIN CommentActivity ca ON rq.QuestionId = ca.PostId
WHERE rq.rn <= 100
AND (rq.QuestionScore > 5 OR rq.AnswerCount > 2 OR rq.FavoriteCount > 1)
ORDER BY rq.QuestionCreationDate DESC;
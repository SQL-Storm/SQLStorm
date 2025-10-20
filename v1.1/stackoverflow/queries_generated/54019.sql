-- {"query": "54019.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1205} 

WITH
-- Extract each tag from each question
question_tags AS (
    SELECT 
        q.Id AS QuestionId,
        q.Score,
        q.AcceptedAnswerId,
        regexp_split_to_table(substring(q.Tags, 2, length(q.Tags)-2), '><') AS TagName,
        q.CreationDate
    FROM Posts q
    WHERE q.PostTypeId = 1
      AND q.CreationDate >= NOW() - INTERVAL '1 year'
),
-- Aggregate answer data per question
answers AS (
    SELECT
        a.ParentId AS QuestionId,
        a.Id AS AnswerId,
        a.Body,
        a.OwnerUserId,
        COUNT(*) FILTER (WHERE a.Score > 0) AS PositiveScore
    FROM Posts a
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId, a.Id, a.Body, a.OwnerUserId
),
-- Count body edits for each answer
answer_edits AS (
    SELECT
        ph.PostId AS AnswerId,
        COUNT(*) AS BodyEditCount
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 5         -- Edit Body
    GROUP BY ph.PostId
),
-- Merge all info together
merged AS (
    SELECT
        qt.QuestionId,
        qt.TagName,
        qt.Score AS QuestionScore,
        qt.AcceptedAnswerId,
        ans.AnswerId,
        ans.Body,
        ans.OwnerUserId,
        COALESCE(ae.BodyEditCount, 0) AS BodyEditCount
    FROM question_tags qt
    LEFT JOIN answers ans ON ans.QuestionId = qt.QuestionId
    LEFT JOIN answer_edits ae ON ae.AnswerId = ans.AnswerId
)
SELECT
    t.TagName,
    COUNT(DISTINCT m.QuestionId)                                 AS QuestionCount,
    AVG(m.QuestionScore)                                        AS AvgQuestionScore,
    COUNT(m.AnswerId)                                            AS TotalAnswers,
    AVG(LENGTH(m.Body))                                          AS AvgAnswerLength,
    AVG(CASE WHEN m.AnswerId = m.AcceptedAnswerId THEN 1.0 ELSE 0.0 END) AS AcceptedAnswerPct,
    COUNT(DISTINCT m.OwnerUserId)                                AS DistinctAnswerUsers,
    SUM(m.BodyEditCount)                                         AS TotalBodyEdits
FROM merged m
JOIN Tags t ON t.TagName = m.TagName
GROUP BY t.TagName
ORDER BY AvgQuestionScore DESC, TotalAnswers DESC
LIMIT 10;

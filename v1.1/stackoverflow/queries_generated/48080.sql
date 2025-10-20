-- {"query": "48080.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 603} 

WITH RankedQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title AS QuestionTitle,
        p.Score AS QuestionScore,
        p.AnswerCount,
        p.ViewCount,
        p.CreationDate AS QuestionCreationDate,
        u.DisplayName AS OwnerDisplayName,
        u.Reputation AS OwnerReputation,
        ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC) AS ViewRank,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS ScoreRank,
        ROW_NUMBER() OVER (ORDER BY p.AnswerCount DESC) AS AnswerCountRank,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate ASC) AS OldestRank
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
      AND p.AnswerCount > 0
      AND p.Score > 100
      AND p.ViewCount > 10000
),
TopAnswers AS (
    SELECT
        a.ParentId AS QuestionId,
        COUNT(a.Id) AS NumberOfTopAnswers,
        SUM(CASE WHEN a.IsAccepted = 1 THEN 1 ELSE 0 END) AS AcceptedAnswerExists
    FROM Posts a
    WHERE a.PostTypeId = 2
      AND a.Score > 50
    GROUP BY a.ParentId
),
QuestionsWithHighActivity AS (
    SELECT
        q.QuestionId,
        q.QuestionTitle,
        q.QuestionScore,
        q.AnswerCount,
        q.ViewCount,
        q.QuestionCreationDate,
        q.OwnerDisplayName,
        q.OwnerReputation,
        ta.NumberOfTopAnswers,
        ta.AcceptedAnswerExists
    FROM RankedQuestions q
    LEFT JOIN TopAnswers ta ON q.QuestionId = ta.QuestionId
    WHERE ta.NumberOfTopAnswers > 5 OR ta.AcceptedAnswerExists = 1
)
SELECT
    qw.QuestionId,
    qw.QuestionTitle,
    qw.QuestionScore,
    qw.AnswerCount,
    qw.ViewCount,
    qw.QuestionCreationDate,
    qw.OwnerDisplayName,
    qw.OwnerReputation,
    qw.NumberOfTopAnswers,
    qw.AcceptedAnswerExists,
    (qw.QuestionScore * 0.4 + qw.ViewCount * 0.3 + qw.AnswerCount * 0.2 + COALESCE(qw.NumberOfTopAnswers, 0) * 0.1) AS CompositeScore
FROM QuestionsWithHighActivity qw
ORDER BY CompositeScore DESC
LIMIT 1000;

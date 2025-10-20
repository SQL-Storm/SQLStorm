-- {"query": "48079.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 507} 
WITH RankedQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title AS QuestionTitle,
        p.CreationDate AS QuestionCreationDate,
        p.Score AS QuestionScore,
        p.OwnerUserId AS QuestionOwnerUserId,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Score > 1000
),
AnsweredQuestions AS (
    SELECT
        q.QuestionId,
        COUNT(a.Id) AS NumberOfAnswers,
        AVG(a.Score) AS AverageAnswerScore
    FROM RankedQuestions q
    JOIN Posts a ON q.QuestionId = a.ParentId AND a.PostTypeId = 2
    WHERE q.rn <= 100
    GROUP BY q.QuestionId
),
TopAnswerers AS (
    SELECT
        a.ParentId AS QuestionId,
        u.DisplayName AS AnswererDisplayName,
        COUNT(a.Id) AS AnswersGivenForQuestion,
        SUM(a.Score) AS TotalAnswerScoreForQuestion,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY COUNT(a.Id) DESC, SUM(a.Score) DESC) AS answerer_rank
    FROM Posts a
    JOIN Users u ON a.OwnerUserId = u.Id
    WHERE a.ParentId IN (SELECT QuestionId FROM AnsweredQuestions)
    GROUP BY a.ParentId, u.DisplayName
)
SELECT
    rq.QuestionId,
    rq.QuestionTitle,
    rq.QuestionCreationDate,
    rq.QuestionScore,
    rq.QuestionOwnerUserId,
    aq.NumberOfAnswers,
    aq.AverageAnswerScore,
    ta.AnswererDisplayName AS TopAnswererForThisQuestion,
    ta.AnswersGivenForQuestion AS TopAnswererAnswersCount,
    ta.TotalAnswerScoreForQuestion AS TopAnswererScore
FROM RankedQuestions rq
JOIN AnsweredQuestions aq ON rq.QuestionId = aq.QuestionId
LEFT JOIN TopAnswerers ta ON rq.QuestionId = ta.QuestionId AND ta.answerer_rank = 1
WHERE rq.rn <= 100
ORDER BY rq.rn;
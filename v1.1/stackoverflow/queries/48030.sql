-- {"query": "48030.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 335} 
WITH RankedQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title AS QuestionTitle,
        p.CreationDate AS QuestionCreationDate,
        u.DisplayName AS QuestionOwnerDisplayName,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
),
AnswerStats AS (
    SELECT
        a.ParentId AS QuestionId,
        COUNT(a.Id) AS AnswerCount,
        AVG(a.Score) AS AverageAnswerScore,
        SUM(CASE WHEN p.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END) AS IsAcceptedAnswer
    FROM Posts a
    JOIN Posts p ON a.ParentId = p.Id
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId
)
SELECT
    rq.QuestionId,
    rq.QuestionTitle,
    rq.QuestionCreationDate,
    rq.QuestionOwnerDisplayName,
    COALESCE(ans.AnswerCount, 0) AS TotalAnswers,
    COALESCE(ans.AverageAnswerScore, 0.0) AS AvgAnswerScore,
    COALESCE(ans.IsAcceptedAnswer, 0) AS AcceptedAnswerPresent
FROM RankedQuestions rq
LEFT JOIN AnswerStats ans ON rq.QuestionId = ans.QuestionId
WHERE rq.rn <= 1000
ORDER BY rq.rn;
-- {"query": "66.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 123} 
WITH RecursiveCTE AS (
    SELECT Id, Title, AnswerCount
    FROM Posts
    WHERE PostTypeId = 1
    
    UNION ALL
    
    SELECT p.Id, p.Title, p.AnswerCount
    FROM Posts p
    INNER JOIN RecursiveCTE c ON p.ParentId = c.Id
)

SELECT c.Id, c.Title, c.AnswerCount, COUNT(cl.Id) AS LinkCount
FROM RecursiveCTE c
LEFT JOIN PostLinks cl ON c.Id = cl.PostId
GROUP BY c.Id, c.Title, c.AnswerCount
ORDER BY LinkCount DESC;
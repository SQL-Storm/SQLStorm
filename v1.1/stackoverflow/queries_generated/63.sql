-- {"query": "63.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 172} 
WITH CTE_Posts AS (
    SELECT p.Id, p.Title, p.Score, b.UserId, b.Name AS BadgeName
    FROM Posts p
    LEFT JOIN Badges b ON p.OwnerUserId = b.UserId
    WHERE p.PostTypeId = 1
),
CTE_CommentCounts AS (
    SELECT p.Id, COUNT(c.Id) AS TotalComments
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    GROUP BY p.Id
)
SELECT p.Id AS QuestionId, p.Title AS QuestionTitle, p.Score AS QuestionScore, p.BadgeName,
    COALESCE(cc.TotalComments, 0) AS TotalComments
FROM CTE_Posts p
LEFT JOIN CTE_CommentCounts cc ON p.Id = cc.Id
ORDER BY p.Score DESC, TotalComments DESC;
-- {"query": "49.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 151} 
WITH cte AS (
    SELECT p.Id AS PostId, p.Title, COUNT(DISTINCT c.UserId) AS NumCommentators
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.PostTypeId = 1
    GROUP BY p.Id
)

SELECT c.PostId, c.Title, c.NumCommentators, vt.Name AS VoteTypeName, vt.Name || ' is interesting' AS Description
FROM cte c
LEFT JOIN Votes v ON c.PostId = v.PostId
LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
WHERE v.CreationDate > (SELECT MAX(CreationDate) FROM Votes)
ORDER BY c.NumCommentators DESC, c.PostId;
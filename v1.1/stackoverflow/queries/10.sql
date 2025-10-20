-- {"query": "10.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 147} 
WITH RECURSIVE cte AS (
    SELECT Id, UserId, CreationDate, Text
    FROM Comments
    WHERE Score > 0
    UNION ALL
    SELECT c.Id, c.UserId, c.CreationDate, c.Text
    FROM Comments c
    JOIN cte p ON c.PostId = p.Id
)
SELECT p.Id AS PostId, p.Title, COUNT(DISTINCT v.UserId) AS TotalVotes, MAX(c.CreationDate) AS LatestCommentDate
FROM Posts p
LEFT JOIN Votes v ON p.Id = v.PostId
JOIN cte c ON p.Id = c.Id
GROUP BY p.Id, p.Title
ORDER BY TotalVotes DESC, LatestCommentDate;
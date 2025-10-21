-- {"query": "30095.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 113} 
SELECT p.Id as PostId,
    p.Title,
    p.Body,
    u.DisplayName as OwnerName,
    COUNT(c.Id) as NumComments,
    SUM(v.VoteTypeId) as TotalVotes
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
GROUP BY p.Id, p.Title, p.Body, u.DisplayName
ORDER BY TotalVotes DESC, NumComments DESC
LIMIT 100;
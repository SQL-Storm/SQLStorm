-- {"query": "30073.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 106} 
SELECT DISTINCT
    p.Id AS PostId,
    p.Title AS PostTitle,
    u.Id AS UserId,
    u.DisplayName AS UserDisplayName,
    p.CreationDate AS PostCreationDate,
    COUNT(v.Id) AS TotalVotes
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON p.Id = v.PostId
GROUP BY p.Id, p.Title, u.Id, u.DisplayName, p.CreationDate
ORDER BY TotalVotes DESC, PostCreationDate ASC;
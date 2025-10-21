-- {"query": "32042.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 288} 
SELECT u.Id AS UserId, u.DisplayName, u.Reputation, p.Id AS PostId, p.Title, p.Score, 
       p.CreationDate AS PostCreationDate, COUNT(com.Id) AS TotalComments, 
       COUNT(v.Id) AS TotalVotes, COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotes, 
       COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotes, 
       COUNT(DISTINCT ps.Id) AS EditCount
FROM Users u
JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Comments com ON p.Id = com.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN PostHistory ps ON p.Id = ps.PostId AND ps.PostHistoryTypeId IN (4, 5, 6)
WHERE u.Reputation > 1000 
  AND p.PostTypeId IN (1, 2)
  AND p.CreationDate >= (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year')
GROUP BY u.Id, u.DisplayName, u.Reputation, p.Id, p.Title, p.Score, p.CreationDate
ORDER BY TotalVotes DESC, UpVotes DESC, p.Score DESC;
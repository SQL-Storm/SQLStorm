-- {"query": "44045.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 103230, "output_tokens": 37668} 
SELECT p.Id, p.CreationDate, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, u.Reputation, u.DisplayName, u.Location, COUNT(v.Id) AS VoteCount, COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVoteCount, COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVoteCount
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON p.Id = v.PostId
WHERE p.PostTypeId = 1 AND p.CreationDate >= '2010-01-01' AND p.CreationDate <= '2010-12-31'
GROUP BY p.Id, p.CreationDate, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, u.Reputation, u.DisplayName, u.Location
ORDER BY VoteCount DESC
LIMIT 100;
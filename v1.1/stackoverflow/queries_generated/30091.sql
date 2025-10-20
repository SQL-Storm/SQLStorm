-- {"query": "30091.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 62} 

SELECT p.Id as PostId, p.Title, p.Body, u.DisplayName as OwnerDisplayName, u.Reputation
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
WHERE p.PostTypeId = 1
ORDER BY p.ViewCount DESC, p.Score DESC;

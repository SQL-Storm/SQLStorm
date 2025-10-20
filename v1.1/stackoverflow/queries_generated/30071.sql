-- {"query": "30071.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 68} 
SELECT * FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
JOIN PostHistory ph ON p.Id = ph.PostId
JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
WHERE p.PostTypeId = 1
AND p.Score > 10
ORDER BY p.LastActivityDate DESC;
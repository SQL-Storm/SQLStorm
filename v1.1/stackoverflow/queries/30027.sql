-- {"query": "30027.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 55} 
SELECT COUNT(*) as total_count
FROM Users u
JOIN Posts p ON u.Id = p.OwnerUserId
JOIN Comments c ON p.Id = c.PostId
JOIN Votes v ON p.Id = v.PostId
JOIN Badges b ON u.Id = b.UserId;
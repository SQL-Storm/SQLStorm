-- {"query": "14017.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 42030, "output_tokens": 18281} 
WITH cte AS (
    SELECT p.Id, p.Title, p.Body, p.Tags, p.OwnerUserId, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes,
           RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS rk
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
)
SELECT *
FROM cte
WHERE rk = 1
ORDER BY Reputation DESC, Views DESC, UpVotes DESC, DownVotes ASC
LIMIT 10;
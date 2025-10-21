-- {"query": "30031.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 91} 

WITH ranked_users AS (
  SELECT Id, Reputation, dense_rank() OVER (ORDER BY Reputation DESC) AS rank
  FROM Users
)
SELECT u.Id, u.DisplayName, u.Reputation, r.rank
FROM Users u
JOIN ranked_users r
ON u.Id = r.Id
WHERE u.CreationDate BETWEEN '2008-01-01' AND '2009-01-01'
ORDER BY r.rank

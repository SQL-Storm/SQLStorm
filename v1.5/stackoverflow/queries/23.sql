-- {"query": "23.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 141} 
WITH ranked_users AS (
    SELECT Id, DisplayName, Reputation, 
           ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS rank
    FROM Users
), highly_rep_users AS (
    SELECT Id, DisplayName, Reputation, rank
    FROM ranked_users
    WHERE rank <= (SELECT COUNT(DISTINCT Id) * 0.1 FROM Users) -- Top 10% users
)
SELECT DISTINCT p.Id, p.Title, p.Score, p.ViewCount, p.Tags, u.DisplayName AS OwnerDisplayName
FROM Posts p
JOIN highly_rep_users u ON p.OwnerUserId = u.Id
WHERE p.PostTypeId = 1
ORDER BY p.Score DESC, p.ViewCount DESC;
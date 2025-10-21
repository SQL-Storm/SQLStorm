-- {"query": "13.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 166} 
WITH ranked_users AS (
    SELECT Id, DisplayName, Reputation,
           ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS rn
    FROM Users
),
top_users AS (
    SELECT Id, DisplayName, Reputation
    FROM ranked_users
    WHERE rn <= 100
)
SELECT p.Id, p.Title, p.Score, p.OwnerUserId,
       u.DisplayName AS OwnerDisplayName, b.UserId AS BadgeUserId,
       CASE
            WHEN p.Score >= 10 THEN 'High Score'
            WHEN p.Score >= 5 THEN 'Medium Score'
            ELSE 'Low Score'
       END AS ScoreLevel
FROM Posts p
JOIN top_users u ON p.OwnerUserId = u.Id
LEFT JOIN Badges b ON b.UserId = p.OwnerUserId
WHERE p.PostTypeId = 1
ORDER BY p.Score DESC;
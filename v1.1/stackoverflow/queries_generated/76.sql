-- {"query": "76.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 178} 
WITH ranked_users AS (
    SELECT
        Id,
        Reputation,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS rn
    FROM Users
),
top_users AS (
    SELECT
        ru.Id,
        ru.Reputation
    FROM ranked_users ru
    WHERE ru.rn <= 100
)
SELECT
    u.Id,
    u.DisplayName,
    u.Location,
    COUNT(DISTINCT p.Id) AS NumPosts,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS NumAnswers,
    SUM(p.Score) AS TotalScore
FROM top_users tu
JOIN Users u ON tu.Id = u.Id
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
WHERE u.Location IS NOT NULL
GROUP BY u.Id, u.DisplayName, u.Location
ORDER BY NumPosts DESC, TotalScore DESC;
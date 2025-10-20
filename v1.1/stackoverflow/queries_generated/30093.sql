-- {"query": "30093.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 46} 
SELECT
    u.DisplayName,
    b.Name,
    COUNT(*) AS BadgeCount
FROM Users u
JOIN Badges b ON u.Id = b.UserId
GROUP BY u.DisplayName, b.Name
ORDER BY BadgeCount DESC;
-- {"query": "30074.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 88} 
SELECT
    u.Id AS UserId,
    SUM(p.Score) AS TotalScore,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT v.Id) AS TotalVotes
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Votes v ON p.Id = v.PostId
GROUP BY u.Id
ORDER BY TotalScore DESC, TotalPosts DESC, TotalVotes DESC;
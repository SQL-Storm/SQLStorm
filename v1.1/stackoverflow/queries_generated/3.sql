-- {"query": "3.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 112} 
SELECT u.DisplayName, u.Reputation, COUNT(DISTINCT p.Id) AS TotalPosts, SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId IN (1, 2)
LEFT JOIN Votes v ON p.Id = v.PostId
WHERE u.Location IS NOT NULL
GROUP BY u.DisplayName, u.Reputation
HAVING TotalPosts > 10
ORDER BY TotalUpVotes DESC;
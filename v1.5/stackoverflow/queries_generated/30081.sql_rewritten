-- {"query": "30081.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 54} 
SELECT Users.Id as UserID, Users.DisplayName, SUM(Votes.BountyAmount) as TotalBountyAmount
FROM Users
JOIN Votes ON Users.Id = Votes.UserId
GROUP BY Users.Id, Users.DisplayName
ORDER BY TotalBountyAmount DESC;
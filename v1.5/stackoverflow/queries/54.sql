-- {"query": "54.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 119} 
WITH RankedUsers AS (
    SELECT Id, DisplayName, Reputation, ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS Rank
    FROM Users
),
TopUsers AS (
    SELECT Id, DisplayName, Reputation
    FROM RankedUsers
    WHERE Rank <= 100
)
SELECT t.Id AS UserId, t.DisplayName AS UserName, SUM(v.BountyAmount) AS TotalBountyAmount
FROM TopUsers t
JOIN Votes v ON t.Id = v.UserId
WHERE v.VoteTypeId = 8
GROUP BY t.Id, t.DisplayName
ORDER BY TotalBountyAmount DESC;
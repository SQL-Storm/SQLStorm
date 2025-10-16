-- {"query": "37.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 154} 
WITH RankedUsers AS (
    SELECT Id, DisplayName, Reputation, ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS Rank
    FROM Users
),
TopUsers AS (
    SELECT Id, DisplayName, Reputation
    FROM RankedUsers
    WHERE Rank <= 100
)
SELECT DISTINCT p.Id, p.Title, p.Score, p.ViewCount, u.DisplayName AS Owner, COUNT(v.Id) AS VoteCount
FROM Posts p
JOIN TopUsers u ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON p.Id = v.PostId
WHERE p.PostTypeId = 1
GROUP BY p.Id, p.Title, p.Score, p.ViewCount, u.DisplayName
ORDER BY VoteCount DESC, p.ViewCount DESC;
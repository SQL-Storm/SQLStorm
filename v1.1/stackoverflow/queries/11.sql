-- {"query": "11.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 103} 
WITH RankUsers AS (
    SELECT Id, DisplayName, Reputation, ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS Rank
    FROM Users
    WHERE Location LIKE 'United States%'
),
TopUsers AS (
    SELECT Id, DisplayName, Reputation, Rank
    FROM RankUsers
    WHERE Rank <= 10
)
SELECT L.Id, L.Name AS LinkType, T.DisplayName AS TopUser, T.Reputation
FROM LinkTypes L
LEFT JOIN TopUsers T ON L.Id = T.Id;
-- {"query": "1.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 122} 
WITH RecursiveUserCount AS (
    SELECT UserId, COUNT(*) AS TotalVotes
    FROM Votes
    WHERE CreationDate >= '2022-01-01'
    GROUP BY UserId

    UNION ALL

    SELECT V.UserId, R.TotalVotes + COUNT(*)
    FROM Votes V
    JOIN RecursiveUserCount R ON V.UserId = R.UserId
    WHERE V.CreationDate >= '2022-01-01'
    GROUP BY V.UserId, R.TotalVotes
)
SELECT UserId, TotalVotes
FROM RecursiveUserCount
WHERE TotalVotes > 100
ORDER BY TotalVotes DESC;
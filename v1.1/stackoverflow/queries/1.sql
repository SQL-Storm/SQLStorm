WITH RECURSIVE RecursiveUserCount AS (
    SELECT UserId, COUNT(*) AS TotalVotes
    FROM Votes
    WHERE CreationDate >= DATE '2022-01-01'
    GROUP BY UserId

    UNION ALL

    SELECT V.UserId, R.TotalVotes + cnt AS TotalVotes
    FROM (
        SELECT V2.UserId, COUNT(*) AS cnt
        FROM Votes V2
        WHERE V2.CreationDate >= DATE '2022-01-01'
        GROUP BY V2.UserId
    ) AS Agg
    JOIN RecursiveUserCount R ON Agg.UserId = R.UserId
    JOIN Votes V ON V.UserId = Agg.UserId
    GROUP BY V.UserId, R.TotalVotes, Agg.cnt
)
SELECT UserId, TotalVotes
FROM RecursiveUserCount
WHERE TotalVotes > 100
ORDER BY TotalVotes DESC;
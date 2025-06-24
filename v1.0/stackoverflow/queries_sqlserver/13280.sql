
SELECT 
    (SELECT COUNT(*) FROM Posts) AS TotalPosts,
    (SELECT COUNT(*) FROM Users) AS TotalUsers,
    (SELECT COUNT(*) FROM Votes) AS TotalVotes,
    AVG(Score) AS AveragePostScore
FROM
    Posts
WHERE
    CreationDate >= DATEADD(YEAR, -1, GETDATE())
GROUP BY
    Score;

WITH RECURSIVE RecursiveCTE AS (
    SELECT Id, Title, AnswerCount
    FROM Posts
    WHERE PostTypeId = 1

    UNION ALL

    SELECT p.Id, p.Title, p.AnswerCount
    FROM Posts p
    INNER JOIN RecursiveCTE c ON p.ParentId = c.Id
)

SELECT c.Id, c.Title, c.AnswerCount, COUNT(cl.Id) AS LinkCount
FROM RecursiveCTE c
LEFT JOIN PostLinks cl ON c.Id = cl.PostId
GROUP BY c.Id, c.Title, c.AnswerCount
ORDER BY LinkCount DESC;

WITH PostStats AS (
    SELECT 
        DATEADD(MONTH, DATEDIFF(MONTH, 0, CreationDate), 0) AS Month,
        COUNT(*) AS TotalPosts,
        SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers
    FROM Posts
    GROUP BY DATEADD(MONTH, DATEDIFF(MONTH, 0, CreationDate), 0)
),
VoteStats AS (
    SELECT 
        DATEADD(MONTH, DATEDIFF(MONTH, 0, CreationDate), 0) AS Month,
        COUNT(*) AS TotalVotes
    FROM Votes
    GROUP BY DATEADD(MONTH, DATEDIFF(MONTH, 0, CreationDate), 0)
),
UserStats AS (
    SELECT 
        DATEADD(MONTH, DATEDIFF(MONTH, 0, CreationDate), 0) AS Month,
        COUNT(*) AS TotalUsers
    FROM Users
    GROUP BY DATEADD(MONTH, DATEDIFF(MONTH, 0, CreationDate), 0)
)
SELECT 
    COALESCE(p.Month, v.Month, u.Month) AS Month,
    COALESCE(p.TotalPosts, 0) AS TotalPosts,
    COALESCE(p.TotalQuestions, 0) AS TotalQuestions,
    COALESCE(p.TotalAnswers, 0) AS TotalAnswers,
    COALESCE(v.TotalVotes, 0) AS TotalVotes,
    COALESCE(u.TotalUsers, 0) AS TotalUsers
FROM PostStats p
FULL OUTER JOIN VoteStats v ON p.Month = v.Month
FULL OUTER JOIN UserStats u ON p.Month = u.Month
ORDER BY Month;

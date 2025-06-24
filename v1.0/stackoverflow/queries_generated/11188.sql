-- Performance benchmarking query to analyze user activity and post statistics

WITH UserPostStats AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName, 
        COUNT(p.Id) AS TotalPosts, 
        COUNT(c.Id) AS TotalComments,
        SUM(v.VoteTypeId = 2) AS TotalUpVotes,  -- Upmod votes
        SUM(v.VoteTypeId = 3) AS TotalDownVotes -- Downmod votes
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON p.Id = v.PostId
    GROUP BY u.Id, u.DisplayName
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        TotalPosts,
        TotalComments,
        TotalUpVotes,
        TotalDownVotes,
        ROW_NUMBER() OVER (ORDER BY TotalPosts DESC) AS RankByPosts,
        ROW_NUMBER() OVER (ORDER BY TotalComments DESC) AS RankByComments
    FROM UserPostStats
)
SELECT 
    UserId,
    DisplayName,
    TotalPosts,
    TotalComments,
    TotalUpVotes,
    TotalDownVotes,
    RankByPosts,
    RankByComments
FROM TopUsers
WHERE RankByPosts <= 10 OR RankByComments <= 10
ORDER BY RankByPosts, RankByComments;

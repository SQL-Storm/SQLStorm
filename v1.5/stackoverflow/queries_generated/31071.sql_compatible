WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COALESCE(SUM(v.BountyAmount), 0) AS TotalBounty,
        SUM(u.UpVotes) AS TotalUpVotes,
        SUM(u.DownVotes) AS TotalDownVotes,
        u.CreationDate
    FROM Users AS u
    LEFT JOIN Posts AS p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments AS c ON u.Id = c.UserId
    LEFT JOIN Votes AS v ON u.Id = v.UserId
    GROUP BY u.Id, u.DisplayName, u.CreationDate
),
RecentPostStats AS (
    SELECT 
        p.OwnerUserId,
        COUNT(CASE WHEN p.CreationDate > (TIMESTAMP '2024-10-01 12:34:56') - INTERVAL '30 days' THEN 1 END) AS RecentPosts,
        COUNT(DISTINCT c.Id) AS RecentComments,
        AVG(p.Score) AS AvgScore,
        AVG(p.ViewCount) AS AvgViews
    FROM Posts AS p
    LEFT JOIN Comments AS c ON p.Id = c.PostId
    WHERE p.CreationDate > (TIMESTAMP '2024-10-01 12:34:56') - INTERVAL '30 days'
    GROUP BY p.OwnerUserId
)
SELECT 
    ua.UserId,
    ua.DisplayName,
    ua.TotalPosts,
    ua.TotalComments,
    ua.TotalBounty,
    ua.TotalUpVotes,
    ua.TotalDownVotes,
    rsa.RecentPosts,
    rsa.RecentComments,
    rsa.AvgScore,
    rsa.AvgViews,
    ua.CreationDate
FROM UserActivity AS ua
JOIN RecentPostStats AS rsa ON ua.UserId = rsa.OwnerUserId
WHERE ua.TotalPosts > 5
ORDER BY ua.TotalUpVotes DESC, rsa.AvgViews DESC
LIMIT 50;
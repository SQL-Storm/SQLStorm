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
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY u.Id, u.DisplayName, u.CreationDate
),
RecentPostStats AS (
    SELECT 
        p.OwnerUserId,
        COUNT(CASE WHEN p.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY THEN 1 END) AS RecentPosts,
        COUNT(DISTINCT c.Id) AS RecentComments,
        AVG(p.Score) AS AvgScore,
        AVG(p.ViewCount) AS AvgViews
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY
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
FROM UserActivity ua
JOIN RecentPostStats rsa ON ua.UserId = rsa.OwnerUserId
WHERE ua.TotalPosts > 5
ORDER BY ua.TotalUpVotes DESC, rsa.AvgViews DESC
LIMIT 50;
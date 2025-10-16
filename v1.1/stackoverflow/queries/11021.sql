WITH RecentPosts AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.CreationDate, 
        p.Score, 
        p.ViewCount, 
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName, 
        u.Reputation,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    WHERE 
        p.CreationDate > (CAST('2024-10-01' AS date) - INTERVAL '30' DAY)
    GROUP BY
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        u.DisplayName,
        u.Reputation
),
UserActivity AS (
    SELECT 
        OwnerUserId AS UserId, 
        COUNT(Id) AS TotalPosts, 
        SUM(Score) AS TotalScore, 
        SUM(ViewCount) AS TotalViews
    FROM 
        Posts
    GROUP BY 
        OwnerUserId
),
TopUsers AS (
    SELECT 
        UserId, 
        TotalPosts, 
        TotalScore, 
        TotalViews
    FROM 
        UserActivity
    WHERE 
        TotalPosts > 10
    ORDER BY 
        TotalScore DESC
    LIMIT 10
)
SELECT 
    rp.Id, 
    rp.Title, 
    rp.CreationDate, 
    rp.Score, 
    rp.ViewCount, 
    rp.OwnerDisplayName, 
    rp.Reputation, 
    rp.UpVotes, 
    rp.DownVotes,
    ua.TotalPosts, 
    ua.TotalScore, 
    ua.TotalViews
FROM 
    RecentPosts rp
JOIN 
    TopUsers tu ON rp.OwnerUserId = tu.UserId
JOIN 
    UserActivity ua ON tu.UserId = ua.UserId
WHERE 
    rp.UpVotes > rp.DownVotes
ORDER BY 
    rp.Score DESC, 
    rp.ViewCount DESC
LIMIT 20;
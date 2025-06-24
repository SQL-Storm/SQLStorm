
WITH RECURSIVE UserScoreCTE AS (
    SELECT 
        Id,
        Reputation,
        0 AS Level
    FROM 
        Users
    WHERE 
        Reputation > 1000
        
    UNION ALL
    
    SELECT 
        u.Id,
        u.Reputation,
        us.Level + 1
    FROM 
        Users u
    JOIN 
        UserScoreCTE us ON u.Reputation > us.Reputation AND us.Level < 3
),
PostRankings AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        @row_number := IF(@prev_owner_user_id = p.OwnerUserId, @row_number + 1, 1) AS Rank,
        @prev_owner_user_id := p.OwnerUserId
    FROM 
        Posts p, (SELECT @row_number := 0, @prev_owner_user_id := NULL) AS init
    WHERE 
        p.CreationDate >= DATE_SUB('2024-10-01', INTERVAL 30 DAY)
    ORDER BY 
        p.OwnerUserId, p.Score DESC, p.CreationDate DESC
),
ClosedPosts AS (
    SELECT 
        ph.PostId, 
        COUNT(*) AS CloseCount
    FROM 
        PostHistory ph
    WHERE 
        ph.PostHistoryTypeId = 10
    GROUP BY 
        ph.PostId
),
UserWithTopPost AS (
    SELECT 
        u.DisplayName,
        up.PostId,
        up.Title,
        ps.CloseCount
    FROM 
        Users u
    JOIN 
        PostRankings up ON u.Id = up.OwnerUserId
    LEFT JOIN 
        ClosedPosts ps ON up.PostId = ps.PostId
    WHERE 
        up.Rank = 1
)

SELECT 
    u.DisplayName,
    u.Reputation,
    COALESCE(ps.CloseCount, 0) AS CloseCount,
    COUNT(b.Id) AS BadgeCount,
    GROUP_CONCAT(DISTINCT p.Title ORDER BY p.Title SEPARATOR ', ') AS TopPosts
FROM 
    Users u
LEFT JOIN 
    UserWithTopPost ps ON u.DisplayName = ps.DisplayName
LEFT JOIN 
    Badges b ON b.UserId = u.Id
LEFT JOIN 
    Posts p ON p.OwnerUserId = u.Id AND p.CreationDate >= DATE_SUB('2024-10-01', INTERVAL 60 DAY)
WHERE 
    u.Reputation IS NOT NULL 
    AND u.Location IS NOT NULL
GROUP BY 
    u.DisplayName, u.Reputation, ps.CloseCount
HAVING 
    AVG(u.Reputation) >= 1000
ORDER BY 
    u.Reputation DESC
LIMIT 10;

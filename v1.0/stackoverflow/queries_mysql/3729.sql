
WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId, 
        p.Title, 
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS Rank,
        COALESCE((SELECT COUNT(*) 
                  FROM Comments c 
                  WHERE c.PostId = p.Id), 0) AS CommentCount
    FROM 
        Posts p
    WHERE 
        p.CreationDate >= NOW() - INTERVAL 1 YEAR
), 
UserReputation AS (
    SELECT 
        u.Id AS UserId, 
        SUM(b.Class) AS TotalBadges,
        SUM(u.Reputation) AS TotalReputation
    FROM 
        Users u
    LEFT JOIN 
        Badges b ON u.Id = b.UserId 
    GROUP BY 
        u.Id
)
SELECT 
    rp.PostId,
    rp.Title,
    rp.Score,
    rp.Rank,
    rp.CommentCount,
    ur.TotalBadges,
    ur.TotalReputation,
    CASE 
        WHEN rp.Rank <= 5 THEN 'Top Post'
        ELSE 'Regular Post' 
    END AS PostCategory,
    CASE 
        WHEN ur.TotalReputation IS NULL THEN 'Reputation not available'
        ELSE CONCAT('User Reputation: ', ur.TotalReputation) 
    END AS UserReputationInfo
FROM 
    RankedPosts rp
LEFT JOIN 
    Users u ON u.Id = rp.PostId 
LEFT JOIN 
    UserReputation ur ON u.Id = ur.UserId 
WHERE 
    rp.Rank <= 10
ORDER BY 
    rp.Score DESC
LIMIT 20;

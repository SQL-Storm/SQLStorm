WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PostRank
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 1
),
UserReputation AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        SUM(v.BountyAmount) AS TotalBounties
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN 
        Votes v ON p.Id = v.PostId AND v.VoteTypeId = 8
    GROUP BY 
        u.Id, u.Reputation
),
ClosePostInfo AS (
    SELECT 
        ph.PostId,
        COUNT(*) AS CloseCount,
        MAX(CASE WHEN ph.CreationDate > CAST('2024-10-01' AS DATE) - INTERVAL '30 days' THEN 1 ELSE 0 END) AS RecentlyClosed
    FROM 
        PostHistory ph
    WHERE 
        ph.PostHistoryTypeId IN (10, 11)
    GROUP BY 
        ph.PostId
)
SELECT 
    up.UserId AS UserIdAlias,
    up.Reputation,
    up.QuestionCount,
    up.TotalBounties,
    rp.Title,
    rp.CreationDate,
    COALESCE(cpi.CloseCount, 0) AS CloseCount,
    CASE 
        WHEN COALESCE(cpi.RecentlyClosed, 0) = 1 THEN 'Recently Closed'
        ELSE 'Active'
    END AS PostStatus
FROM 
    UserReputation up
JOIN 
    RankedPosts rp ON up.UserId = rp.OwnerUserId
LEFT JOIN 
    ClosePostInfo cpi ON rp.Id = cpi.PostId
WHERE 
    up.Reputation > 1000
    AND rp.PostRank = 1
ORDER BY 
    up.Reputation DESC, up.QuestionCount DESC;
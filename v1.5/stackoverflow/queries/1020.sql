WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId, 
        p.Title, 
        p.Score, 
        p.ViewCount, 
        p.CreationDate, 
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS ScoreRank,
        COUNT(*) OVER (PARTITION BY p.PostTypeId) AS TotalPosts
    FROM 
        Posts p
    WHERE 
        p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
),
UserActivity AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPostsCreated,
        SUM(COALESCE(v.BountyAmount, 0)) AS TotalBounty,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    GROUP BY 
        u.Id, u.DisplayName
),
ClosedPostInfo AS (
    SELECT 
        ph.PostId,
        COUNT(*) AS CloseActions,
        MAX(ph.CreationDate) AS LastCloseDate
    FROM 
        PostHistory ph
    WHERE 
        ph.PostHistoryTypeId = 10
    GROUP BY 
        ph.PostId
)
SELECT 
    rp.PostId,
    rp.Title,
    rp.Score,
    rp.ViewCount,
    rp.ScoreRank,
    u.DisplayName,
    u.TotalPostsCreated,
    u.TotalBounty,
    u.TotalUpVotes,
    c.CloseActions,
    c.LastCloseDate
FROM 
    RankedPosts rp
JOIN 
    UserActivity u ON rp.PostId = u.UserId
LEFT JOIN 
    ClosedPostInfo c ON rp.PostId = c.PostId
WHERE 
    rp.ScoreRank <= 10
ORDER BY 
    rp.Score DESC, 
    u.TotalBounty DESC 
LIMIT 50;
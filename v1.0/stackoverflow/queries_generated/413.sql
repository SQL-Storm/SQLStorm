WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS Rank
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 1 AND 
        p.Score IS NOT NULL
),
UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(SUM(v.BountyAmount), 0) AS TotalBounties,
        COALESCE(SUM(v.CreationDate <= NOW() - INTERVAL '1 year' AND v.VoteTypeId = 2), 0) AS YearlyUpvotes
    FROM 
        Users u
    LEFT JOIN 
        Votes v ON u.Id = v.UserId
    GROUP BY 
        u.Id
),
ClosedQuestions AS (
    SELECT 
        ph.PostId,
        COUNT(*) AS CloseCount
    FROM 
        PostHistory ph
    WHERE 
        ph.PostHistoryTypeId IN (10, 11)
    GROUP BY 
        ph.PostId
)
SELECT 
    u.UserId,
    u.DisplayName,
    u.Reputation,
    u.TotalBounties,
    u.YearlyUpvotes,
    rp.PostId,
    rp.Title,
    rp.Score,
    rp.CreationDate,
    COALESCE(cq.CloseCount, 0) AS CloseCount
FROM 
    UserStats u
LEFT JOIN 
    RankedPosts rp ON u.UserId = rp.OwnerUserId
LEFT JOIN 
    ClosedQuestions cq ON rp.PostId = cq.PostId
WHERE 
    u.Reputation > 1000
ORDER BY 
    u.Reputation DESC, 
    rp.Score DESC NULLS LAST
LIMIT 50;

WITH RecentPosts AS (
    SELECT 
        p.Id,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        p.Tags,
        COUNT(c.Id) AS CommentCount
    FROM 
        Posts p
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    WHERE 
        p.CreationDate >= NOW() - INTERVAL '30 days'
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.OwnerUserId, p.Tags
)
SELECT 
    rp.*,
    CASE 
        WHEN rp.CommentCount > 10 THEN 'Popular' 
        ELSE 'Less Popular' 
    END AS Popularity
FROM 
    RecentPosts rp
ORDER BY 
    rp.CreationDate DESC;


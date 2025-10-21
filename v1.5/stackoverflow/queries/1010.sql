WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS UserRank
    FROM 
        Posts p
    WHERE 
        p.CreationDate > CAST('2024-10-01' AS DATE) - INTERVAL '1 year'
        AND p.PostTypeId = 1
),
UserStatistics AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalUpvotes,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS TotalDownvotes,
        COUNT(DISTINCT b.Id) AS BadgeCount
    FROM 
        Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE 
        u.Reputation > 1000
    GROUP BY 
        u.Id, u.DisplayName
),
ClosedPostDetails AS (
    SELECT 
        p.Id AS PostId,
        COUNT(ph.Id) AS CloseCount,
        MAX(ph.CreationDate) AS LastClosed
    FROM 
        Posts p
    LEFT JOIN 
        PostHistory ph ON ph.PostId = p.Id
        AND ph.PostHistoryTypeId = 10
    WHERE 
        p.PostTypeId = 1
    GROUP BY 
        p.Id
),
PostLinksSummary AS (
    SELECT 
        pl.PostId,
        COUNT(pl.RelatedPostId) AS LinkedPostsCount
    FROM 
        PostLinks pl
    GROUP BY 
        pl.PostId
)
SELECT 
    us.UserId,
    us.DisplayName,
    us.TotalUpvotes,
    us.TotalDownvotes,
    us.BadgeCount,
    rp.PostId,
    rp.Title,
    rp.Score,
    rp.ViewCount,
    COALESCE(cp.CloseCount, 0) AS CloseCount,
    cp.LastClosed,
    COALESCE(pl.LinkedPostsCount, 0) AS LinkedPostsCount,
    CASE 
        WHEN COALESCE(cp.CloseCount, 0) > 0 THEN 'Closed'
        ELSE 'Open'
    END AS PostStatus
FROM 
    UserStatistics us
JOIN 
    RankedPosts rp ON us.UserId = rp.OwnerUserId
LEFT JOIN 
    ClosedPostDetails cp ON rp.PostId = cp.PostId
LEFT JOIN 
    PostLinksSummary pl ON rp.PostId = pl.PostId
WHERE 
    rp.UserRank <= 3
ORDER BY 
    us.TotalUpvotes DESC, rp.Score DESC;
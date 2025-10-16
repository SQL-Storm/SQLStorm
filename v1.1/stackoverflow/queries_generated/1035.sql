-- {"query": "1035.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 555} 

WITH RankedPosts AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.CreationDate,
        p.Score, 
        p.ViewCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM 
        Posts p
    WHERE 
        p.CreationDate >= NOW() - INTERVAL '1 year' 
        AND p.PostTypeId = 1
),
UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COALESCE(SUM(v.BountyAmount), 0) AS TotalBounties,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalUpvotes,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS TotalDownvotes,
        COUNT(DISTINCT b.Id) AS BadgeCount
    FROM 
        Users u
    LEFT JOIN 
        Votes v ON u.Id = v.UserId
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    GROUP BY 
        u.Id
),
PostDetails AS (
    SELECT 
        rp.Id AS PostId,
        rp.Title,
        rp.CreationDate,
        us.DisplayName,
        us.TotalBounties,
        us.TotalUpvotes,
        us.TotalDownvotes,
        us.BadgeCount,
        COUNT(c.Id) AS CommentCount,
        COALESCE(SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END), 0) AS CloseCount
    FROM 
        RankedPosts rp
    JOIN 
        Users us ON rp.OwnerUserId = us.Id
    LEFT JOIN 
        Comments c ON rp.Id = c.PostId
    LEFT JOIN 
        PostHistory ph ON rp.Id = ph.PostId
    GROUP BY 
        rp.Id, us.DisplayName, us.TotalBounties, us.TotalUpvotes, us.TotalDownvotes, us.BadgeCount
)
SELECT 
    pd.PostId,
    pd.Title,
    pd.CreationDate,
    pd.DisplayName,
    pd.TotalBounties,
    pd.TotalUpvotes,
    pd.TotalDownvotes,
    pd.BadgeCount,
    pd.CommentCount,
    pd.CloseCount
FROM 
    PostDetails pd
WHERE 
    pd.CommentCount > 5 
    AND pd.CloseCount = 0
ORDER BY 
    pd.TotalUpvotes DESC, pd.CreationDate DESC
LIMIT 10;

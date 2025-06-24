WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        COALESCE((SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id), 0) AS CommentCount,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS Rank
    FROM 
        Posts p
    WHERE 
        p.CreationDate >= NOW() - INTERVAL '1 year' -- Only consider posts from the last year
),
UserBadges AS (
    SELECT 
        u.Id AS UserId,
        COUNT(b.Id) AS BadgeCount,
        STRING_AGG(b.Name, ', ') AS BadgeNames
    FROM 
        Users u
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    GROUP BY 
        u.Id
),
PostActivities AS (
    SELECT 
        ph.PostId,
        ph.PostHistoryTypeId,
        COUNT(*) AS ActivityCount
    FROM 
        PostHistory ph
    WHERE 
        ph.CreationDate >= NOW() - INTERVAL '6 months' 
        AND ph.PostHistoryTypeId IN (10, 11, 12, 13) -- Only relevant types: Close, Reopen, Delete, Undelete
    GROUP BY 
        ph.PostId, ph.PostHistoryTypeId
),
FilteredPosts AS (
    SELECT 
        rp.PostId,
        rp.Title,
        rp.CreationDate,
        rp.Score,
        rp.CommentCount,
        ub.BadgeCount,
        ub.BadgeNames,
        SUM(CASE WHEN pa.PostHistoryTypeId = 10 THEN pa.ActivityCount ELSE 0 END) AS CloseCount,
        SUM(CASE WHEN pa.PostHistoryTypeId = 11 THEN pa.ActivityCount ELSE 0 END) AS ReopenCount,
        SUM(CASE WHEN pa.PostHistoryTypeId = 12 THEN pa.ActivityCount ELSE 0 END) AS DeleteCount,
        SUM(CASE WHEN pa.PostHistoryTypeId = 13 THEN pa.ActivityCount ELSE 0 END) AS UndeleteCount
    FROM 
        RankedPosts rp
    LEFT JOIN 
        UserBadges ub ON rp.PostId = ub.UserId -- Cross-reference user badges
    LEFT JOIN 
        PostActivities pa ON rp.PostId = pa.PostId 
    WHERE 
        rb.Rank <= 5 -- Only consider top-ranked posts in each type
    GROUP BY 
        rp.PostId, rp.Title, rp.CreationDate, rp.Score, rp.CommentCount, ub.BadgeCount, ub.BadgeNames
)
SELECT 
    fp.PostId,
    fp.Title,
    fp.CreationDate,
    fp.Score,
    fp.CommentCount,
    fp.BadgeCount,
    fp.BadgeNames,
    fp.CloseCount,
    fp.ReopenCount,
    fp.DeleteCount,
    fp.UndeleteCount,
    CASE 
        WHEN fp.CommentCount > 0 THEN 'Active'
        ELSE 'Inactive' 
    END AS PostStatus, 
    CASE 
        WHEN fp.CloseCount > 0 THEN 'Closed'
        ELSE NULL 
    END AS ClosureStatus
FROM 
    FilteredPosts fp
WHERE 
    fp.BadgeCount > 2 -- Select posts from users with more than 2 badges
ORDER BY 
    fp.Score DESC, fp.CreationDate ASC;

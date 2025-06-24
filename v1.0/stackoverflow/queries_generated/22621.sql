WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.CreationDate,
        p.ViewCount,
        p.AcceptedAnswerId,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate DESC) AS Rank
    FROM 
        Posts p
    WHERE 
        p.CreationDate >= '2023-01-01' AND
        p.Score > 10
),
UserBadgeCounts AS (
    SELECT 
        u.Id AS UserId,
        COUNT(b.Id) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM 
        Users u
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    GROUP BY 
        u.Id
),
PostHistoryAggregate AS (
    SELECT 
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (10, 11) THEN 1 END) AS CloseCount,
        MAX(ph.CreationDate) AS LastChangeDate
    FROM 
        PostHistory ph
    WHERE 
        ph.CreationDate >= '2023-01-01'
    GROUP BY 
        ph.PostId
)
SELECT 
    rp.PostId,
    rp.Title,
    rp.Score,
    rp.ViewCount,
    ub.BadgeCount,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    pha.CloseCount,
    pha.LastChangeDate
FROM 
    RankedPosts rp
LEFT JOIN 
    Users u ON u.Id = (SELECT OwnerUserId FROM Posts WHERE Id = rp.PostId)
LEFT JOIN 
    UserBadgeCounts ub ON u.Id = ub.UserId
LEFT JOIN 
    PostHistoryAggregate pha ON rp.PostId = pha.PostId
WHERE 
    (pha.CloseCount IS NULL OR pha.CloseCount < 2) AND
    (ub.BadgeCount IS NOT NULL AND ub.BadgeCount >= 1) AND
    rp.Rank <= 5
ORDER BY 
    rp.Score DESC, rp.ViewCount DESC, rp.PostId;

This SQL query incorporates various complex constructs for performance benchmarking, including:

- Common Table Expressions (CTEs) to aggregate post rankings, user badge counts, and post history changes.
- Window functions (`ROW_NUMBER()`) defining rankings of posts within each post type based on scores and creation date.
- LEFT JOINs to connect users and badge counts with posts, allowing for null handling where applicable.
- Complicated predicates with conditions on post closure counts and badge counts, including NULL logic.
- Overall ordering applied to highlight high-scoring popular posts.

This query is designed to return top-ranked posts from 2023 with user badge information while filtering out posts with multiple closure actions.

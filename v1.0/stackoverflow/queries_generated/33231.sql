WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId, 
        p.Title, 
        p.ViewCount, 
        p.LastActivityDate, 
        p.Score, 
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS PostRank
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 1 -- Only questions
),
UserDetails AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(b.Id) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM 
        Users u
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    GROUP BY 
        u.Id, u.DisplayName, u.Reputation
),
ClosedPosts AS (
    SELECT 
        ph.PostId, 
        COUNT(*) AS CloseCount, 
        MAX(ph.CreationDate) AS LastClosedDate
    FROM 
        PostHistory ph
    WHERE 
        ph.PostHistoryTypeId = 10 -- Closed posts
    GROUP BY 
        ph.PostId
),
PostMetrics AS (
    SELECT 
        rp.PostId,
        rp.Title,
        ud.DisplayName,
        ud.Reputation,
        ud.BadgeCount,
        ud.GoldBadges,
        ud.SilverBadges,
        ud.BronzeBadges,
        COALESCE(cp.CloseCount, 0) AS CloseCount,
        COALESCE(cp.LastClosedDate, '1900-01-01') AS LastClosedDate
    FROM 
        RankedPosts rp
    JOIN 
        UserDetails ud ON rp.OwnerUserId = ud.UserId
    LEFT JOIN 
        ClosedPosts cp ON rp.PostId = cp.PostId
)
SELECT 
    pm.Title,
    pm.DisplayName,
    pm.Reputation,
    pm.BadgeCount,
    pm.GoldBadges,
    pm.SilverBadges,
    pm.BronzeBadges,
    pm.CloseCount,
    pm.LastClosedDate,
    pm.ViewCount
FROM 
    PostMetrics pm
WHERE 
    pm.CloseCount > 0 
    AND pm.Reputation >= 1000 -- Only consider users with reputation 1000 or more
ORDER BY 
    pm.ViewCount DESC, 
    pm.Reputation DESC
LIMIT 10;

-- This query provides an analysis of posts closed by users who have a high reputation
-- and their associated metrics, including badges, view count, and how many times 
-- their posts were closed, offering insight into the community's engagement and 
-- expertise level in handling questions.

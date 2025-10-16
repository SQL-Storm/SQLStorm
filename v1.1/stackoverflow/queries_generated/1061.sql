-- {"query": "1061.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 547} 

WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS Rank
    FROM 
        Posts p
    WHERE 
        p.CreationDate >= DATEADD(year, -1, GETDATE()) 
        AND p.Score > 0
),
BadgedUsers AS (
    SELECT 
        u.Id AS UserId,
        COUNT(b.Id) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgeCount
    FROM 
        Users u
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    GROUP BY 
        u.Id
    HAVING 
        COUNT(b.Id) > 0
),
PostsWithUserBadges AS (
    SELECT 
        rp.PostId,
        rp.Title,
        rp.Score,
        bu.UserId,
        bu.BadgeCount,
        bu.GoldBadgeCount
    FROM 
        RankedPosts rp
    JOIN 
        Posts p ON rp.PostId = p.Id
    LEFT JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        BadgedUsers bu ON u.Id = bu.UserId
    WHERE 
        bu.BadgeCount IS NOT NULL
)
SELECT 
    p.Title,
    p.Score,
    COUNT(c.Id) AS CommentCount,
    MAX(CASE WHEN b.PostHistoryTypeId = 10 THEN b.CreationDate END) AS ClosedDate,
    COUNT(DISTINCT pl.RelatedPostId) AS RelatedPostCount,
    COALESCE(u.DisplayName, 'Anonymous') AS OwnerDisplayName,
    p.CreationDate AS PostCreationDate,
    CASE 
        WHEN bu.GoldBadgeCount > 0 THEN 'Gold'
        ELSE 'No Gold Badge'
    END AS BadgeStatus
FROM 
    PostsWithUserBadges p
LEFT JOIN 
    Comments c ON p.PostId = c.PostId
LEFT JOIN 
    PostHistory b ON p.PostId = b.PostId 
LEFT JOIN 
    PostLinks pl ON p.PostId = pl.PostId
LEFT JOIN 
    Users u ON p.UserId = u.Id
WHERE 
    p.Score > 10
GROUP BY 
    p.PostId, p.Title, p.Score, u.DisplayName, p.CreationDate, bu.GoldBadgeCount
HAVING 
    COUNT(c.Id) > 5
ORDER BY 
    p.Score DESC, p.PostCreationDate DESC;

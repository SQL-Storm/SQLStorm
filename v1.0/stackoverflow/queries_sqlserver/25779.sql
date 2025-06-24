
WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Body,
        p.CreationDate,
        p.ViewCount,
        p.Score,
        COUNT(c.Id) AS CommentCount,
        STRING_AGG(DISTINCT t.TagName, ',') AS Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS Rank
    FROM 
        Posts p
    LEFT JOIN 
        Comments c ON c.PostId = p.Id
    CROSS APPLY 
        (SELECT value AS TagName 
         FROM STRING_SPLIT(SUBSTRING(p.Tags, 2, LEN(p.Tags)-2), '><')) AS t
        ) AS t
    WHERE 
        p.PostTypeId = 1 AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS DATETIME) - INTERVAL '1 year'
    GROUP BY 
        p.Id, p.Title, p.Body, p.CreationDate, p.ViewCount, p.Score, p.OwnerUserId
),

UserReputation AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(b.Id) AS BadgeCount
    FROM 
        Users u
    LEFT JOIN 
        Badges b ON b.UserId = u.Id
    WHERE 
        u.Reputation > 1000
    GROUP BY 
        u.Id, u.DisplayName, u.Reputation
)

SELECT 
    up.PostId,
    up.Title,
    up.Body,
    up.CreationDate,
    up.ViewCount,
    up.Score,
    up.CommentCount,
    up.Tags,
    ur.DisplayName AS OwnerDisplayName,
    ur.Reputation AS OwnerReputation,
    ur.BadgeCount AS OwnerBadgeCount
FROM 
    RankedPosts up
JOIN 
    Users u ON u.Id = (SELECT OwnerUserId FROM Posts WHERE Id = up.PostId)
JOIN 
    UserReputation ur ON ur.UserId = u.Id
WHERE 
    up.Rank <= 5
ORDER BY 
    up.Score DESC, up.ViewCount DESC;

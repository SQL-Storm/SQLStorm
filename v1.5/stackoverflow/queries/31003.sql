WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        u.DisplayName AS OwnerName,
        COUNT(c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY p.Score DESC, p.CreationDate DESC) AS Rank
    FROM 
        Posts p
    LEFT JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    WHERE 
        p.PostTypeId = 1
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.Score, u.DisplayName
),
TopPosts AS (
    SELECT 
        PostId,
        Title,
        CreationDate,
        Score,
        OwnerName,
        CommentCount,
        VoteCount
    FROM 
        RankedPosts
    WHERE 
        Rank <= 10
)
SELECT 
    tp.PostId,
    tp.Title,
    tp.CreationDate,
    tp.Score,
    tp.OwnerName,
    tp.CommentCount,
    tp.VoteCount,
    COALESCE(BadgeCounts.GoldBadgeCount, 0) AS GoldBadgeCount,
    COALESCE(BadgeCounts.SilverBadgeCount, 0) AS SilverBadgeCount,
    COALESCE(BadgeCounts.BronzeBadgeCount, 0) AS BronzeBadgeCount
FROM 
    TopPosts tp
LEFT JOIN (
    SELECT 
        CAST(UserId AS VARCHAR) AS UserId,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadgeCount,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadgeCount,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadgeCount
    FROM 
        Badges
    GROUP BY 
        UserId
) AS BadgeCounts ON tp.OwnerName = BadgeCounts.UserId
ORDER BY 
    tp.Score DESC, tp.CreationDate DESC;
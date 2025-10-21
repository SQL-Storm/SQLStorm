WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.CreationDate,
        p.ViewCount,
        u.DisplayName AS OwnerName,
        COUNT(c.Id) AS CommentCount,
        COUNT(DISTINCT b.Id) AS BadgeCount
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Badges b ON b.UserId = u.Id
    WHERE 
        p.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '1 year'
    GROUP BY 
        p.Id, p.Title, p.Score, p.CreationDate, p.ViewCount, u.DisplayName
),
ScoredPosts AS (
    SELECT 
        PostId,
        Title,
        Score,
        CreationDate,
        ViewCount,
        OwnerName,
        CommentCount,
        BadgeCount,
        CASE
            WHEN Score IS NULL AND ViewCount IS NULL THEN 0
            ELSE ROW_NUMBER() OVER (ORDER BY Score DESC NULLS LAST, ViewCount DESC NULLS LAST)
        END AS Rank
    FROM 
        RankedPosts
)
SELECT 
    PostId,
    Title,
    Score,
    CreationDate,
    ViewCount,
    OwnerName,
    CommentCount,
    BadgeCount,
    Rank
FROM 
    ScoredPosts
WHERE 
    Rank <= 20
ORDER BY 
    Rank;
WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS Rank,
        COUNT(c.Id) OVER (PARTITION BY p.Id) AS CommentCount,
        p.OwnerUserId
    FROM 
        Posts p
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    WHERE 
        p.CreationDate >= (DATE '2024-10-01' - INTERVAL '1' YEAR)
),
FilteredPosts AS (
    SELECT 
        rp.PostId,
        rp.Title,
        rp.CreationDate,
        rp.Score,
        rp.ViewCount,
        rp.Rank,
        rp.CommentCount,
        rp.OwnerUserId,
        CASE 
            WHEN rp.Score > 100 THEN 'High Score'
            WHEN rp.Score BETWEEN 50 AND 100 THEN 'Moderate Score'
            ELSE 'Low Score'
        END AS ScoreCategory,
        (SELECT AVG(p2.Score) FROM Posts p2 WHERE p2.OwnerUserId = rp.OwnerUserId) AS AvgScoreByUser
    FROM 
        RankedPosts rp
    WHERE 
        rp.Rank = 1 AND 
        rp.CommentCount > 5
)
SELECT 
    fp.PostId,
    fp.Title,
    fp.CreationDate,
    fp.Score,
    fp.ViewCount,
    fp.ScoreCategory,
    COALESCE(fp.AvgScoreByUser, 0) AS AvgScoreByUser
FROM 
    FilteredPosts fp
JOIN 
    Users u ON u.Id = fp.OwnerUserId
LEFT OUTER JOIN 
    PostHistory ph ON ph.PostId = fp.PostId
WHERE 
    u.Reputation > 1000 AND 
    (ph.Comment IS NULL OR ph.Comment NOT LIKE '%duplicate%')
ORDER BY 
    fp.Score DESC, 
    fp.ViewCount DESC
LIMIT 100;
WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS RankScore,
        COUNT(c.Id) AS CommentCount
    FROM 
        Posts p
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    WHERE 
        p.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.PostTypeId, p.Score
), 

FilteredPosts AS (
    SELECT 
        r.PostId, 
        r.Title, 
        r.Score, 
        r.ViewCount, 
        r.CommentCount,
        CASE 
            WHEN r.RankScore <= 5 THEN 'Top'
            ELSE 'Other'
        END AS ScoreCategory
    FROM 
        RankedPosts r
    WHERE 
        r.CommentCount > 0
), 

PostMetrics AS (
    SELECT 
        f.PostId,
        f.Title,
        f.Score, 
        f.ViewCount,
        f.CommentCount,
        f.ScoreCategory,
        CASE 
            WHEN f.Score IS NULL THEN 0 
            ELSE f.Score * 1.0 / NULLIF(f.ViewCount, 0)
        END AS ScorePerView
    FROM 
        FilteredPosts f
), 

UserBadges AS (
    SELECT 
        u.Id AS UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(
            CASE 
                WHEN b.Class = 1 THEN 3 -- Gold
                WHEN b.Class = 2 THEN 2 -- Silver
                WHEN b.Class = 3 THEN 1 -- Bronze
                ELSE 0
            END
        ) AS BadgePoints
    FROM 
        Users u
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    WHERE 
        u.Reputation > 1000 
    GROUP BY 
        u.Id
)

SELECT 
    p.PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.ScoreCategory,
    p.ScorePerView,
    u.TotalBadges,
    u.BadgePoints,
    p.ScorePerView * COALESCE(u.BadgePoints, 0) AS ScoreWhenAwarded
FROM 
    PostMetrics p
LEFT JOIN 
    UserBadges u ON p.PostId = (SELECT OwnerUserId FROM Posts WHERE Id = p.PostId)
WHERE 
    p.ScorePerView IS NOT NULL
ORDER BY 
    ScoreWhenAwarded DESC
LIMIT 100;

This query performs a comprehensive analysis of posts made in the last year, ranking them based on their score and integrating user badge metrics. It employs Common Table Expressions (CTEs) for modularity, uses window functions for ranking, handles NULL logic, and computes a derived column that multiplies the score per view by badge points to derive additional metrics, thus showcasing intricate SQL capabilities while being performance-oriented.

WITH PostMetrics AS (
    SELECT 
        p.Id AS PostId, 
        p.Title, 
        p.ViewCount, 
        p.Score,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS Upvotes,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS Downvotes,
        COUNT(c.Id) AS CommentCount,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS RankInType,
        MAX(b.Date) FILTER (WHERE b.Class = 1) AS LastGoldBadgeDate,
        MAX(b.Date) FILTER (WHERE b.Class = 2) AS LastSilverBadgeDate,
        MAX(b.Date) FILTER (WHERE b.Class = 3) AS LastBronzeBadgeDate 
    FROM 
        Posts p
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Badges b ON p.OwnerUserId = b.UserId
    GROUP BY 
        p.Id
),
FilteredPosts AS (
    SELECT 
        PostId, 
        Title, 
        ViewCount, 
        Score, 
        Upvotes, 
        Downvotes, 
        CommentCount,
        RankInType, 
        LastGoldBadgeDate, 
        LastSilverBadgeDate, 
        LastBronzeBadgeDate
    FROM 
        PostMetrics
    WHERE 
        ViewCount > (SELECT AVG(ViewCount) FROM Posts) -- Retaining posts above average views
        AND (LastGoldBadgeDate IS NOT NULL OR LastSilverBadgeDate IS NOT NULL OR LastBronzeBadgeDate IS NOT NULL) -- Users must have at least one badge
),
FinalSelection AS (
    SELECT 
        *,
        CASE 
            WHEN ViewCount > 1000 THEN 'High Traffic'
            WHEN ViewCount BETWEEN 500 AND 1000 THEN 'Medium Traffic'
            ELSE 'Low Traffic'
        END AS TrafficCategory
    FROM 
        FilteredPosts
)

SELECT 
    fs.PostId,
    fs.Title,
    fs.ViewCount,
    fs.Score,
    fs.Upvotes,
    fs.Downvotes,
    fs.CommentCount,
    fs.RankInType,
    fs.LastGoldBadgeDate,
    fs.LastSilverBadgeDate,
    fs.LastBronzeBadgeDate,
    fs.TrafficCategory,
    (SELECT AVG(ViewCount) FROM FilteredPosts WHERE RankInType = fs.RankInType) AS AvgViewCountByType,
    CASE 
        WHEN fs.Score IS NULL THEN 'Unscored Post'
        ELSE 'Scored Post'
    END AS PostScoreStatus
FROM 
    FinalSelection fs
WHERE 
    fs.RankInType < 5 -- Top 4 posts in each type 
ORDER BY 
    fs.TrafficCategory DESC, 
    fs.Score DESC;

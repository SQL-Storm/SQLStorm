
WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.CreationDate,
        u.DisplayName AS OwnerDisplayName,
        COUNT(c.Id) AS CommentCount,
        @row_number := IF(@prev_post_type = p.PostTypeId, @row_number + 1, 1) AS PostRank,
        @prev_post_type := p.PostTypeId,
        COALESCE(NULLIF(p.LastActivityDate, p.CreationDate), p.LastEditDate) AS LastActive
    FROM 
        Posts p
    LEFT JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    CROSS JOIN (SELECT @row_number := 0, @prev_post_type := NULL) AS vars
    WHERE 
        p.Score >= 0
    GROUP BY 
        p.Id, p.Title, p.Score, p.CreationDate, u.DisplayName, p.LastActivityDate, p.LastEditDate
),
FilteredPosts AS (
    SELECT 
        rp.PostId,
        rp.Title,
        rp.Score,
        rp.CreationDate,
        rp.OwnerDisplayName,
        rp.CommentCount,
        rp.PostRank,
        CASE 
            WHEN rp.CommentCount > 0 THEN 'Active'
            ELSE 'Inactive'
        END AS ActivityStatus
    FROM 
        RankedPosts rp
    WHERE 
        rp.PostRank <= 5 
),
PostStatistics AS (
    SELECT 
        f.OwnerDisplayName,
        COUNT(f.PostId) AS PostsCount,
        SUM(f.Score) AS TotalScore,
        AVG(f.Score) AS AvgScore,
        MAX(f.CreationDate) AS LatestPostDate,
        GROUP_CONCAT(DISTINCT CASE WHEN f.ActivityStatus = 'Active' THEN f.Title END) AS ActivePosts
    FROM 
        FilteredPosts f
    GROUP BY 
        f.OwnerDisplayName
)
SELECT 
    ps.OwnerDisplayName,
    ps.PostsCount,
    ps.TotalScore,
    ps.AvgScore,
    ps.LatestPostDate,
    CASE 
        WHEN ps.PostsCount IS NULL THEN 'No Posts'
        WHEN ps.AvgScore > 20 THEN 'Highly Engaged'
        ELSE 'Moderately Engaged'
    END AS EngagementLevel,
    COALESCE(ps.ActivePosts, 'No Active Posts') AS ActivePostsList
FROM 
    PostStatistics ps
ORDER BY 
    ps.TotalScore DESC;

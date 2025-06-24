WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        COUNT(c.Id) AS CommentCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS Rank,
        COALESCE(NULLIF(AVG(v.BountyAmount), 0), 0) AS AverageBounty
    FROM 
        Posts p
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId AND v.VoteTypeId = 9 -- BountyClose
    WHERE 
        p.PostTypeId = 1 -- Questions only
        AND p.CreationDate > NOW() - INTERVAL '1 year'
    GROUP BY 
        p.Id
),
RecentActivities AS (
    SELECT 
        ph.PostId,
        MAX(ph.CreationDate) AS LastEditDate,
        STRING_AGG(CONCAT(ph.UserDisplayName, ': ', ph.Comment), '; ') AS EditComments
    FROM 
        PostHistory ph
    WHERE 
        ph.PostHistoryTypeId IN (4, 5, 24) -- Edit Title, Edit Body, Suggested Edit Applied
    GROUP BY 
        ph.PostId
)
SELECT 
    rp.PostId,
    rp.Title,
    rp.ViewCount,
    rp.Score,
    rp.AverageBounty,
    ra.LastEditDate,
    ra.EditComments,
    CASE 
        WHEN rp.CommentCount > 10 THEN 'Highly Engaged'
        WHEN rp.CommentCount BETWEEN 5 AND 10 THEN 'Moderately Engaged'
        ELSE 'Low Engagement'
    END AS EngagementLevel
FROM 
    RankedPosts rp
LEFT JOIN 
    RecentActivities ra ON rp.PostId = ra.PostId
WHERE 
    rp.Rank <= 3 -- Top 3 posts per user
    AND rp.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) -- Above average score
ORDER BY 
    rp.Score DESC, 
    rp.CreationDate DESC;

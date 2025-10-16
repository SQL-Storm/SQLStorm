-- {"query": "1083.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 601} 

WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS RN
    FROM 
        Posts p
    WHERE 
        p.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
        AND p.Score IS NOT NULL
),
UserEngagement AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COALESCE(SUM(v.BountyAmount), 0) AS TotalBounties,
        COALESCE(COUNT(c.Id), 0) AS TotalComments,
        COALESCE(SUM(p.ViewCount), 0) AS TotalViews
    FROM 
        Users u
    LEFT JOIN 
        Votes v ON u.Id = v.UserId
    LEFT JOIN 
        Comments c ON u.Id = c.UserId
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    GROUP BY 
        u.Id
),
RecentTopPost AS (
    SELECT 
        rp.PostId, 
        rp.Title,
        ue.UserId,
        ue.DisplayName,
        ue.TotalBounties,
        ue.TotalComments,
        ue.TotalViews,
        ROW_NUMBER() OVER (ORDER BY rp.Score DESC) AS TopPostRanking
    FROM 
        RankedPosts rp
    JOIN 
        UserEngagement ue ON rp.OwnerUserId = ue.UserId
    WHERE 
        rp.RN = 1
)

SELECT 
    rp.Title AS RecentTopPost,
    ue.DisplayName,
    ue.TotalBounties,
    ue.TotalComments,
    ue.TotalViews
FROM 
    RecentTopPost rp
JOIN 
    UserEngagement ue ON rp.UserId = ue.UserId
WHERE 
    ue.TotalBounties > 0 OR ue.TotalComments > 10
ORDER BY 
    rp.TopPostRanking, ue.TotalViews DESC;

SELECT 
    DISTINCT CASE 
        WHEN Tags.TagName IS NOT NULL THEN Tags.TagName 
        ELSE 'No Tags' 
    END AS TagName, 
    COUNT(p.Id) AS PostsCount
FROM 
    Tags
LEFT JOIN 
    Posts p ON p.Tags LIKE CONCAT('%', Tags.TagName, '%')
GROUP BY 
    Tags.TagName
HAVING 
    COUNT(p.Id) > 5
ORDER BY 
    PostsCount DESC;

WITH CommonCloseReasons AS (
    SELECT 
        ph.Comment, 
        COUNT(*) AS CloseReasonCount
    FROM 
        PostHistory ph
    WHERE 
        ph.PostHistoryTypeId = 10
    GROUP BY 
        ph.Comment
    ORDER BY 
        CloseReasonCount DESC
)
SELECT 
    * 
FROM 
    CommonCloseReasons
WHERE 
    CloseReasonCount > 5;

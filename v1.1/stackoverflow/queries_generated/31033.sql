-- {"query": "31033.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 370} 

WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        u.DisplayName AS OwnerName,
        p.Score,
        p.ViewCount,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS Rank
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.CreationDate >= NOW() - INTERVAL '1 year'
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        COUNT(DISTINCT p.Id) AS PostsCreated,
        SUM(COALESCE(v.BountyAmount, 0)) AS TotalBounties,
        SUM(COALESCE(c.CommentCount, 0)) AS CommentsCount
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        (SELECT PostId, COUNT(*) AS CommentCount FROM Comments GROUP BY PostId) c ON p.Id = c.PostId
    LEFT JOIN 
        Votes v ON u.Id = v.UserId
    GROUP BY 
        u.Id
    HAVING 
        COUNT(DISTINCT p.Id) > 0
)
SELECT 
    rp.PostId,
    rp.Title,
    rp.OwnerName,
    rp.Score,
    rp.ViewCount,
    ua.PostsCreated,
    ua.TotalBounties,
    ua.CommentsCount
FROM 
    RankedPosts rp
JOIN 
    UserActivity ua ON rp.OwnerName = ua.DisplayName
WHERE 
    rp.Rank <= 5
ORDER BY 
    rp.Score DESC, ua.TotalBounties DESC, ua.CommentsCount DESC;

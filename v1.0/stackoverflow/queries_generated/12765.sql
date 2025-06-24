-- Performance benchmarking query for StackOverflow schema
WITH PostAnalytics AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        COUNT(c.Id) AS CommentCount,
        COUNT(v.Id) AS VoteCount,
        MAX(p.LastActivityDate) AS LastActivity
    FROM 
        Posts p
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    WHERE 
        p.CreationDate >= '2023-01-01'  -- filter for posts created in 2023
    GROUP BY 
        p.Id, p.Title, p.Score, p.ViewCount
),
UserMetrics AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(b.Id) AS BadgeCount,
        SUM(COALESCE(p.ViewCount, 0)) AS TotalViews
    FROM 
        Users u
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    GROUP BY 
        u.Id, u.DisplayName, u.Reputation
)
SELECT 
    pa.PostId,
    pa.Title,
    pa.Score,
    pa.ViewCount,
    pa.CommentCount,
    pa.VoteCount,
    pa.LastActivity,
    um.UserId,
    um.DisplayName,
    um.Reputation,
    um.BadgeCount,
    um.TotalViews
FROM 
    PostAnalytics pa
JOIN 
    Users um ON pa.UserId = um.Id
ORDER BY 
    pa.Score DESC, pa.ViewCount DESC
LIMIT 100; -- Limit the results for benchmarking

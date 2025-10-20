-- {"query": "2004.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 440} 

WITH RankedBadges AS (
    SELECT 
        b.UserId, 
        b.Name, 
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) AS BadgeRank
    FROM 
        Badges b
),
LatestBadges AS (
    SELECT 
        rb.UserId, 
        rb.Name AS LatestBadgeName
    FROM 
        RankedBadges rb
    WHERE 
        rb.BadgeRank = 1
),
ActiveUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation
    FROM 
        Users u
    WHERE 
        u.LastAccessDate > NOW() - INTERVAL '30 days'
),
PopularPosts AS (
    SELECT 
        p.OwnerUserId,
        p.Id AS PostId,
        COUNT(c.Id) AS CommentCount
    FROM 
        Posts p
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    WHERE 
        p.CreationDate > NOW() - INTERVAL '1 year' AND 
        p.Score > 10
    GROUP BY 
        p.OwnerUserId, p.Id
),
UserStatistics AS (
    SELECT 
        au.UserId,
        au.DisplayName,
        au.Reputation,
        lb.LatestBadgeName,
        SUM(pp.CommentCount) AS TotalComments
    FROM 
        ActiveUsers au
    LEFT JOIN 
        LatestBadges lb ON au.UserId = lb.UserId
    LEFT JOIN 
        PopularPosts pp ON au.UserId = pp.OwnerUserId
    GROUP BY 
        au.UserId, au.DisplayName, au.Reputation, lb.LatestBadgeName
)
SELECT 
    us.UserId,
    us.DisplayName,
    COALESCE(us.LatestBadgeName, 'No Badge') AS RecentBadge,
    COALESCE(us.TotalComments, 0) AS TotalCommentCount,
    us.Reputation
FROM 
    UserStatistics us
WHERE 
    us.Reputation > 1000 OR us.TotalComments > 50
ORDER BY 
    us.Reputation DESC, us.TotalCommentCount DESC;

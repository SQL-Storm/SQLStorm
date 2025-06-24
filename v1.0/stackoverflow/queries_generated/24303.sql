WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS RankByScore
    FROM 
        Posts p
    WHERE 
        p.CreationDate >= NOW() - INTERVAL '1 year'
), 
UserScores AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    GROUP BY 
        u.Id, u.Reputation
),
PostsWithBadges AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        b.Name AS BadgeName,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY b.Date DESC) AS BadgeRank
    FROM 
        Posts p
    LEFT JOIN 
        Badges b ON p.OwnerUserId = b.UserId
    WHERE 
        b.Class = 1 -- Gold badges only
)
SELECT 
    u.DisplayName,
    us.Reputation,
    COALESCE(ps.BadgeName, 'No Badge') AS LatestBadge,
    SUM(ps.Score) AS TotalScore,
    SUM(COALESCE(rp.Score, 0)) AS YearlyTopScores,
    COUNT(DISTINCT p.Id) FILTER (WHERE rp.RankByScore <= 5) AS Top5Posts,
    COUNT(DISTINCT c.Id) AS CommentCount
FROM 
    Users u
JOIN 
    UserScores us ON u.Id = us.UserId
LEFT JOIN 
    PostsWithBadges ps ON u.Id = p.OwnerUserId
LEFT JOIN 
    Posts p ON p.OwnerUserId = u.Id
LEFT JOIN 
    RankedPosts rp ON rp.PostId = p.Id
LEFT JOIN 
    Comments c ON c.PostId = p.Id
WHERE 
    us.PostCount > 0
GROUP BY 
    u.Id, u.DisplayName, us.Reputation, ps.BadgeName
HAVING 
    SUM(ps.Score) > 0 OR COUNT(DISTINCT p.Id) > 1
ORDER BY 
    us.Reputation DESC, TotalScore DESC
LIMIT 10;

This SQL query is built on a Stack Overflow-like schema and utilizes various SQL constructs as requested. It employs Common Table Expressions (CTEs) for organizing intermediate results and makes use of window functions to rank posts and badges. The main query aggregates user and post data while considering performance-related metrics, thus providing a robust way to benchmark performance in terms of posts and user engagement. The use of outer joins allows for capturing users without posts and those without badges, while filtering conditions ensure that only meaningful contributions are collected. Unusual cases are handled through the `COALESCE` function and filtering logic to ensure that the results are both valid and insightful.

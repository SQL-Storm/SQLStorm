-- {"query": "42100.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 594} 

SELECT 
    u.DisplayName AS User,
    COUNT(p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
    SUM(p.Score) AS TotalScore,
    COUNT(DISTINCT ph.Id) AS PostHistoryCount,
    COUNT(DISTINCT v.Id) AS VoteCount,
    COUNT(DISTINCT c.Id) AS CommentCount,
    COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (10, 11)) AS CloseReopenCount,
    COUNT(DISTINCT pl.Id) AS PostLinkCount,
    COUNT(DISTINCT t.Id) AS TagCount,
    MAX(p.CreationDate) AS LatestActivity,
    MIN(p.CreationDate) AS FirstActivity,
    AVG(p.ViewCount) AS AvgViews,
    MAX(p.ViewCount) AS MaxViews,
    MIN(p.ViewCount) AS MinViews,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS Favorites,
    COUNT(DISTINCT b.Id) AS BadgeCount,
    MAX(b.Date) AS LatestBadgeDate,
    MIN(b.Date) AS FirstBadgeDate
FROM 
    Users u
JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Comments c ON p.Id = c.PostId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId OR p.Id = pl.RelatedPostId
LEFT JOIN 
    Tags t ON p.Id = t.ExcerptPostId OR p.Id = t.WikiPostId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
WHERE 
    u.CreationDate BETWEEN '2010-01-01' AND '2020-12-31'
GROUP BY 
    u.DisplayName
HAVING 
    COUNT(p.Id) > 10 AND COUNT(DISTINCT ph.Id) > 5 AND COUNT(DISTINCT v.Id) > 20
ORDER BY 
    TotalScore DESC, TotalPosts DESC
LIMIT 100;

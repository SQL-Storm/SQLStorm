SELECT
    p.PostTypeId,
    pt.Name AS PostTypeName,
    COUNT(*) AS TotalPosts,
    AVG(p.Score) AS AverageScore,
    SUM(p.ViewCount) AS TotalViews,
    COUNT(DISTINCT p.OwnerUserId) AS UniqueAuthors,
    COUNT(DISTINCT c.UserId) AS CommentCountDistinctUsers,
    MIN(p.CreationDate) AS EarliestPostDate,
    MAX(p.CreationDate) AS LatestPostDate,
    COUNT(DISTINCT v.UserId) AS VotersCount,
    COUNT(DISTINCT pl.RelatedPostId) AS LinkedPostsCount,
    COUNT(DISTINCT CASE WHEN ba.Class = 1 THEN ba.UserId END) AS GoldBadgesCount,
    COUNT(DISTINCT CASE WHEN ba.Class = 2 THEN ba.UserId END) AS SilverBadgesCount,
    COUNT(DISTINCT CASE WHEN ba.Class = 3 THEN ba.UserId END) AS BronzeBadgesCount,
    COUNT(DISTINCT u.Id) AS RegisteredUsersCount
FROM
    Posts p
JOIN
    PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN
    Comments c ON c.PostId = p.Id
LEFT JOIN
    Votes v ON v.PostId = p.Id
LEFT JOIN
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN
    PostLinks pl ON pl.PostId = p.Id OR pl.RelatedPostId = p.Id
LEFT JOIN
    PostHistory ph ON ph.PostId = p.Id
LEFT JOIN
    Badges ba ON ba.UserId = u.Id
WHERE
    p.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '1 year'
GROUP BY
    p.PostTypeId,
    pt.Name
ORDER BY
    TotalPosts DESC
LIMIT 10;
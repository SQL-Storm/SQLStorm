SELECT
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
    AVG(p.Score) AS AvgScore,
    COALESCE(SUM(v2.VoteCount), 0) AS TotalUpvotes,
    COALESCE(SUM(v3.VoteCount), 0) AS TotalDownvotes,
    COUNT(DISTINCT b.Id) AS BadgesEarned,
    COALESCE(MAX(p.LastActivityDate), u.CreationDate) AS LastActivityDate
FROM
    Users AS u
LEFT JOIN
    Posts AS p ON u.Id = p.OwnerUserId
LEFT JOIN
    (SELECT PostId, COUNT(*) AS VoteCount FROM Votes WHERE VoteTypeId = 2 GROUP BY PostId) AS v2 ON p.Id = v2.PostId
LEFT JOIN
    (SELECT PostId, COUNT(*) AS VoteCount FROM Votes WHERE VoteTypeId = 3 GROUP BY PostId) AS v3 ON p.Id = v3.PostId
LEFT JOIN
    Badges AS b ON u.Id = b.UserId
GROUP BY
    u.DisplayName
    , u.Id
HAVING
    COUNT(DISTINCT p.Id) > 100
ORDER BY
    TotalPosts DESC,
    AvgScore DESC,
    COALESCE(MAX(p.LastActivityDate), u.CreationDate) DESC
LIMIT 10;
SELECT
    u.DisplayName AS UserDisplayName,
    COUNT(p.Id) AS NumberOfPosts,
    SUM(p.Score) AS TotalScore,
    AVG(p.ViewCount) AS AverageViewCount,
    MAX(p.CreationDate) AS LatestPostDate,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
    (SELECT AVG(CAST(Score AS FLOAT)) FROM Comments c WHERE c.UserId = u.Id) AS AverageCommentScore,
    (SELECT COUNT(DISTINCT ph.PostId) FROM PostHistory ph WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId IN (4, 5, 6)) AS NumberOfEdits
FROM
    Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
WHERE
    p.CreationDate >= DATE_TRUNC('year', TIMESTAMP '2024-10-01 12:34:56')
GROUP BY
    u.DisplayName,
    u.Id
HAVING
    COUNT(p.Id) > 100
ORDER BY
    SUM(p.Score) DESC,
    AVG(p.ViewCount) DESC
LIMIT 10;
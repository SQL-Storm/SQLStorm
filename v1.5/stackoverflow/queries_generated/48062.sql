-- {"query": "48062.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 331} 

SELECT
    u.DisplayName AS UserDisplayName,
    COUNT(p.Id) AS NumberOfPosts,
    SUM(p.Score) AS TotalScore,
    AVG(p.ViewCount) AS AverageViewCount,
    MAX(p.CreationDate) AS LatestPostDate,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
    (SELECT AVG(CAST(Score AS REAL)) FROM Comments c WHERE c.UserId = u.Id) AS AverageCommentScore,
    (SELECT COUNT(DISTINCT ph.PostId) FROM PostHistory ph WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId IN (4, 5, 6)) AS NumberOfEdits
FROM
    Users u
JOIN
    Posts p ON u.Id = p.OwnerUserId
WHERE
    p.CreationDate >= DATE('now', '-1 year') -- Posts from the last year
GROUP BY
    u.DisplayName
HAVING
    NumberOfPosts > 100 -- Users with more than 100 posts
ORDER BY
    TotalScore DESC,
    AverageViewCount DESC
LIMIT 10;

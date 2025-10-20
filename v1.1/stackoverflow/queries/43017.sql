SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.Score > 10 THEN 1 ELSE 0 END) AS HighScorePosts,
    AVG(ph.RevisionCount) AS AvgRevisionsPerPost,
    SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS TotalClosedPosts,
    b.TotalBadges,
    ROW_NUMBER() OVER (ORDER BY (COUNT(DISTINCT p.Id) + SUM(CASE WHEN p.Score > 10 THEN 1 ELSE 0 END)) DESC) AS UserRank
FROM
    Users u
LEFT JOIN (
    SELECT 
        OwnerUserId,
        Id,
        Score,
        (SELECT COUNT(*) FROM PostHistory WHERE PostId = p.Id) AS RevisionCount
    FROM 
        Posts p
    WHERE
        p.PostTypeId IN (1, 2)
) p ON u.Id = p.OwnerUserId
LEFT JOIN (
    SELECT 
        UserId,
        COUNT(*) AS TotalBadges
    FROM 
        Badges
    GROUP BY 
        UserId
) b ON u.Id = b.UserId
LEFT JOIN (
    SELECT
        PostId,
        PostHistoryTypeId,
        COUNT(*) OVER (PARTITION BY PostId) AS RevisionCount
    FROM
        PostHistory
) ph ON p.Id = ph.PostId
WHERE 
    u.LastAccessDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '3' MONTH)
GROUP BY 
    u.DisplayName,
    u.Reputation,
    b.TotalBadges,
    ph.RevisionCount
HAVING 
    COUNT(DISTINCT p.Id) > 10
ORDER BY 
    TotalPosts DESC, 
    AvgRevisionsPerPost DESC
LIMIT 100;
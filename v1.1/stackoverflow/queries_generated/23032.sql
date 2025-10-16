-- {"query": "23032.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2685, "output_tokens": 853} 

WITH RankedUsers AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        ROW_NUMBER() OVER (PARTITION BY u.Location ORDER BY u.Reputation DESC) AS RankInLocation,
        COALESCE(u.WebsiteUrl, 'No Website') AS Website,
        SUM(COALESCE(v.BountyAmount, 0)) AS TotalBounty
    FROM Users u
    LEFT JOIN Votes v ON v.UserId = u.Id AND v.VoteTypeId = 8
    WHERE u.Reputation > 1000 AND (u.Location IS NOT NULL OR u.WebsiteUrl LIKE '%http%')
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Location, u.WebsiteUrl
    HAVING SUM(COALESCE(v.BountyAmount, 0)) > 0
),
PostMetrics AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.Title,
        STRING_AGG(SUBSTRING(t.TagName, 1, 10), ', ') AS ShortTags,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 1) AS HighScoreComments,
        CASE 
            WHEN p.ClosedDate IS NULL THEN 'Open' 
            ELSE 'Closed' 
        END AS Status
    FROM Posts p
    INNER JOIN Tags t ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId = 1 AND p.ViewCount > 10000
    GROUP BY p.Id, p.OwnerUserId, p.Score, p.ViewCount, p.Title, p.ClosedDate
),
CorrelatedEdits AS (
    SELECT 
        ph.PostId,
        COUNT(ph.Id) AS EditCount,
        MAX(ph.CreationDate) AS LastEdit,
        (SELECT AVG(Score) FROM Votes v WHERE v.PostId = ph.PostId AND v.VoteTypeId IN (2, 3)) AS AvgVoteScore
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) AND EXISTS (
        SELECT 1 FROM PostLinks pl WHERE pl.PostId = ph.PostId AND pl.LinkTypeId = 3
    )
    GROUP BY ph.PostId
)
SELECT 
    ru.UserId,
    ru.DisplayName,
    ru.RankInLocation,
    ru.Website,
    ru.TotalBounty,
    pm.PostId,
    pm.Title,
    pm.ShortTags,
    pm.HighScoreComments,
    pm.Status,
    ce.EditCount,
    ce.LastEdit,
    ce.AvgVoteScore,
    LAG(pm.Score) OVER (PARTITION BY ru.UserId ORDER BY pm.ViewCount DESC) AS PrevPostScore,
    CASE 
        WHEN ce.AvgVoteScore IS NULL THEN ru.Reputation * 0.1 
        ELSE ru.Reputation + ce.AvgVoteScore 
    END AS AdjustedReputation
FROM RankedUsers ru
LEFT OUTER JOIN PostMetrics pm ON pm.OwnerUserId = ru.UserId
INNER JOIN CorrelatedEdits ce ON ce.PostId = pm.PostId
WHERE ru.RankInLocation <= 5
UNION ALL
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    NULL AS RankInLocation,
    COALESCE(u.WebsiteUrl, 'Unknown') AS Website,
    0 AS TotalBounty,
    NULL AS PostId,
    NULL AS Title,
    NULL AS ShortTags,
    0 AS HighScoreComments,
    'No Posts' AS Status,
    0 AS EditCount,
    NULL AS LastEdit,
    NULL AS AvgVoteScore,
    NULL AS PrevPostScore,
    u.Reputation AS AdjustedReputation
FROM Users u
WHERE u.Id NOT IN (SELECT UserId FROM RankedUsers)
AND u.Reputation BETWEEN 500 AND 1000
AND NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1)
ORDER BY AdjustedReputation DESC
LIMIT 100;

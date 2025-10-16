-- {"query": "23071.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2685, "output_tokens": 1185} 

WITH UserBadgeCTE AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(COUNT(b.Id), 0) AS BadgeCount,
        STRING_AGG(CASE WHEN b.Class = 1 THEN CONCAT(b.Name, ' (Gold)') 
                        WHEN b.Class = 2 THEN CONCAT(b.Name, ' (Silver)') 
                        ELSE CONCAT(b.Name, ' (Bronze)') END, '; ') AS BadgeList,
        ROW_NUMBER() OVER (PARTITION BY u.Location ORDER BY COUNT(b.Id) DESC) AS BadgeRank
    FROM Users u
    LEFT OUTER JOIN Badges b ON u.Id = b.UserId AND b.TagBased = 1
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
    HAVING COUNT(b.Id) > 0 OR u.Reputation > 1000
),
PostStatsCTE AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 0) AS PositiveComments,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousScore,
        CASE 
            WHEN p.Title IS NULL THEN 'Untitled'
            WHEN LENGTH(p.Title) > 50 THEN SUBSTRING(p.Title, 1, 50) || '...'
            ELSE p.Title 
        END AS ProcessedTitle,
        COALESCE(p.AnswerCount, 0) + COALESCE(p.FavoriteCount, 0) AS EngagementScore
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)  -- Questions and Answers
      AND (p.ClosedDate IS NULL OR p.ClosedDate > CURRENT_TIMESTAMP - INTERVAL '1 year')
),
TagUsageCTE AS (
    SELECT 
        t.Id AS TagId,
        t.TagName,
        t.Count AS TagCount,
        RANK() OVER (ORDER BY t.Count DESC) AS TagPopularityRank
    FROM Tags t
    WHERE t.IsRequired = 0 OR t.IsRequired IS NULL
)
SELECT 
    ub.UserId,
    ub.DisplayName,
    ub.Reputation,
    ub.BadgeCount,
    ub.BadgeList,
    ub.BadgeRank,
    ps.PostId,
    ps.Score,
    ps.ViewCount,
    ps.PositiveComments,
    COALESCE(ps.PreviousScore, 0) AS PreviousScore,
    ps.ProcessedTitle,
    ps.EngagementScore,
    tu.TagName,
    tu.TagCount,
    tu.TagPopularityRank,
    CASE 
        WHEN ps.EngagementScore > 10 THEN 'High Engagement'
        WHEN ps.EngagementScore BETWEEN 5 AND 10 THEN 'Medium Engagement'
        ELSE 'Low Engagement'
    END AS EngagementLevel,
    (ub.Reputation * 1.0 / NULLIF(ub.BadgeCount + 1, 0)) AS AvgRepPerBadge
FROM UserBadgeCTE ub
FULL OUTER JOIN PostStatsCTE ps ON ub.UserId = ps.OwnerUserId
LEFT JOIN Tags t ON ps.ProcessedTitle LIKE '%' || t.TagName || '%'
LEFT JOIN TagUsageCTE tu ON t.Id = tu.TagId
WHERE ub.BadgeRank <= 5
   OR EXISTS (SELECT 1 FROM Votes v WHERE v.PostId = ps.PostId AND v.VoteTypeId = 2 AND v.CreationDate > CURRENT_TIMESTAMP - INTERVAL '6 months')
UNION
SELECT 
    NULL AS UserId,
    'Anonymous' AS DisplayName,
    0 AS Reputation,
    0 AS BadgeCount,
    NULL AS BadgeList,
    NULL AS BadgeRank,
    p.Id AS PostId,
    p.Score,
    p.ViewCount,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 0) AS PositiveComments,
    NULL AS PreviousScore,
    CASE WHEN p.Title IS NULL THEN 'Untitled' ELSE p.Title END AS ProcessedTitle,
    COALESCE(p.AnswerCount, 0) + COALESCE(p.FavoriteCount, 0) AS EngagementScore,
    NULL AS TagName,
    NULL AS TagCount,
    NULL AS TagPopularityRank,
    'N/A' AS EngagementLevel,
    NULL AS AvgRepPerBadge
FROM Posts p
WHERE p.OwnerUserId IS NULL
  AND p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = p.PostTypeId)
EXCEPT
SELECT 
    ub.UserId,
    ub.DisplayName,
    ub.Reputation,
    ub.BadgeCount,
    ub.BadgeList,
    ub.BadgeRank,
    ps.PostId,
    ps.Score,
    ps.ViewCount,
    ps.PositiveComments,
    COALESCE(ps.PreviousScore, 0) AS PreviousScore,
    ps.ProcessedTitle,
    ps.EngagementScore,
    tu.TagName,
    tu.TagCount,
    tu.TagPopularityRank,
    CASE 
        WHEN ps.EngagementScore > 10 THEN 'High Engagement'
        WHEN ps.EngagementScore BETWEEN 5 AND 10 THEN 'Medium Engagement'
        ELSE 'Low Engagement'
    END AS EngagementLevel,
    (ub.Reputation * 1.0 / NULLIF(ub.BadgeCount + 1, 0)) AS AvgRepPerBadge
FROM UserBadgeCTE ub
INNER JOIN PostStatsCTE ps ON ub.UserId = ps.OwnerUserId
INNER JOIN TagUsageCTE tu ON 1=1  -- Dummy join for complexity
WHERE ub.BadgeCount = 0
ORDER BY Reputation DESC, Score DESC;

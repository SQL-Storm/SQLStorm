-- {"query": "23005.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2685, "output_tokens": 783} 
WITH ActiveUsers AS (
    SELECT u.Id, u.Reputation, u.DisplayName,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RepRank,
           COUNT(b.Id) AS BadgeCount,
           STRING_AGG(CASE WHEN b.Class = 1 THEN b.Name ELSE NULL END, ', ') AS GoldBadges
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000 AND u.LastAccessDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
    GROUP BY u.Id, u.Reputation, u.DisplayName
    HAVING COUNT(CASE WHEN b.Class = 1 THEN 1 END) >= 1
),
QuestionStats AS (
    SELECT p.Id AS PostId, p.Title, p.Score, p.ViewCount,
           (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 0) AS PositiveComments,
           COALESCE((SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 8), 0) AS AvgBounty,
           RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS UserQuestionRank
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags LIKE '%sql%' AND (p.ClosedDate IS NULL OR p.ClosedDate > p.CreationDate + INTERVAL '30 days')
),
EditHistory AS (
    SELECT ph.PostId, COUNT(ph.Id) AS EditCount,
           MAX(ph.CreationDate) AS LastEdit,
           STRING_AGG(COALESCE(ph.UserDisplayName, 'Anonymous'), '; ') AS Editors
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6,7,8,9) AND ph.Comment IS NOT NULL
    GROUP BY ph.PostId
    HAVING COUNT(ph.Id) > 5
)
SELECT au.DisplayName, au.RepRank, au.BadgeCount, au.GoldBadges,
       qs.Title, qs.Score, qs.ViewCount, qs.PositiveComments, qs.AvgBounty, qs.UserQuestionRank,
       eh.EditCount, eh.LastEdit, eh.Editors,
       CASE WHEN qs.Score * qs.ViewCount > 100000 THEN 'High Impact' ELSE 'Standard' END AS ImpactLevel,
       (qs.Score + COALESCE(eh.EditCount, 0) + qs.PositiveComments) * (1 + au.RepRank / 10.0) AS CalculatedMetric
FROM ActiveUsers au
INNER JOIN QuestionStats qs ON au.Id = (SELECT OwnerUserId FROM Posts WHERE Id = qs.PostId)
LEFT OUTER JOIN EditHistory eh ON qs.PostId = eh.PostId
WHERE au.RepRank <= 100
UNION ALL
SELECT NULL AS DisplayName, NULL AS RepRank, NULL AS BadgeCount, NULL AS GoldBadges,
       p.Title, p.Score, p.ViewCount,
       (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 0) AS PositiveComments,
       COALESCE((SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 8), 0) AS AvgBounty,
       NULL AS UserQuestionRank,
       NULL AS EditCount, NULL AS LastEdit, NULL AS Editors,
       CASE WHEN p.Score * p.ViewCount > 100000 THEN 'High Impact' ELSE 'Standard' END AS ImpactLevel,
       p.Score * p.ViewCount AS CalculatedMetric
FROM Posts p
WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NULL AND p.Tags LIKE '%performance%'
ORDER BY CalculatedMetric DESC
LIMIT 1000;
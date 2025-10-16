-- {"query": "23061.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2685, "output_tokens": 681} 

WITH ActiveUsers AS (
    SELECT u.Id, u.Reputation, u.Location,
           ROW_NUMBER() OVER (PARTITION BY COALESCE(u.Location, 'Unknown') ORDER BY u.Reputation DESC) AS LocationRank,
           COUNT(p.Id) AS PostCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
    GROUP BY u.Id, u.Reputation, u.Location
    HAVING COUNT(p.Id) > 10
),
PostMetrics AS (
    SELECT p.Id AS PostId, p.Title, p.Tags,
           (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 8) AS AvgBounty,
           string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') AS TagArray,
           COALESCE((SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 0), 0) AS PositiveComments
    FROM Posts p
    WHERE p.PostTypeId = 1  -- Questions
    AND EXISTS (SELECT 1 FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (10, 11))  -- Closed and reopened
),
RankedBadges AS (
    SELECT b.UserId, b.Class,
           COUNT(*) AS BadgeCount,
           MAX(b.Date) AS LatestBadgeDate
    FROM Badges b
    WHERE b.TagBased = TRUE
    GROUP BY b.UserId, b.Class
)
SELECT au.DisplayName || ' (' || COALESCE(au.Location, 'N/A') || ')' AS UserInfo,
       pm.Title,
       (SELECT STRING_AGG(pl.RelatedPostId::text, ', ')
        FROM PostLinks pl
        WHERE pl.PostId = pm.PostId AND pl.LinkTypeId = 3) AS Duplicates,
       CASE
           WHEN au.LocationRank = 1 THEN 'Top in Location'
           WHEN au.LocationRank <= 3 THEN 'High Rank'
           ELSE 'Other'
       END AS RankCategory,
       rb.BadgeCount AS GoldBadges,
       pm.AvgBounty,
       pm.PositiveComments,
       NULLIF(array_to_string(pm.TagArray, ', '), '') AS TagsList
FROM ActiveUsers au
INNER JOIN Posts p ON au.Id = p.OwnerUserId
LEFT OUTER JOIN PostMetrics pm ON p.Id = pm.PostId
LEFT JOIN RankedBadges rb ON au.Id = rb.UserId AND rb.Class = 1
WHERE au.PostCount > (SELECT AVG(PostCount) FROM ActiveUsers)
UNION ALL
SELECT 'Anonymous' AS UserInfo,
       p.Title,
       NULL AS Duplicates,
       'N/A' AS RankCategory,
       0 AS GoldBadges,
       NULL AS AvgBounty,
       COALESCE((SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id), 0) AS PositiveComments,
       substring(p.Tags, 2, length(p.Tags)-2) AS TagsList
FROM Posts p
WHERE p.OwnerUserId IS NULL AND p.PostTypeId = 1
ORDER BY GoldBadges DESC NULLS LAST, PositiveComments DESC;

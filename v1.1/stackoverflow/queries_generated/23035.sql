-- {"query": "23035.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2685, "output_tokens": 814} 

WITH ActiveUsers AS (
    SELECT u.Id, u.Reputation, u.DisplayName,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS UserRank,
           COALESCE(u.Location, 'Unknown') AS UserLocation
    FROM Users u
    WHERE u.Reputation > 1000
      AND u.CreationDate > '2010-01-01'
),
PopularPosts AS (
    SELECT p.Id, p.PostTypeId, p.OwnerUserId, p.Score, p.ViewCount, p.Tags,
           NTILE(5) OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS ScoreQuintile,
           CASE WHEN p.Tags IS NULL THEN 'No Tags' ELSE CONCAT('<', REPLACE(p.Tags, '><', '>, <'), '>') END AS FormattedTags
    FROM Posts p
    WHERE p.Score > 0 OR p.ViewCount > 100
),
UserBadges AS (
    SELECT b.UserId, COUNT(b.Id) AS BadgeCount,
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
           MAX(b.Date) AS LatestBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
PostActivity AS (
    SELECT ph.PostId, COUNT(ph.Id) AS EditCount,
           (SELECT COUNT(c.Id) FROM Comments c WHERE c.PostId = ph.PostId AND c.Score > 0) AS PositiveComments
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6,7,8,9)
    GROUP BY ph.PostId
    HAVING COUNT(ph.Id) > 1
)
SELECT au.Id AS UserId, au.DisplayName, au.UserRank, au.UserLocation,
       pp.Id AS PostId, pp.Score, pp.ViewCount, pp.FormattedTags,
       ub.BadgeCount, ub.GoldBadges, ub.LatestBadgeDate,
       pa.EditCount, pa.PositiveComments,
       COALESCE((SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = pp.Id AND v.VoteTypeId = 8 AND v.BountyAmount IS NOT NULL), 0) AS AvgBounty,
       CASE WHEN pp.Score > 50 THEN 'High Score' WHEN pp.Score BETWEEN 10 AND 50 THEN 'Medium Score' ELSE 'Low Score' END AS ScoreCategory
FROM ActiveUsers au
LEFT OUTER JOIN PopularPosts pp ON au.Id = pp.OwnerUserId
LEFT OUTER JOIN UserBadges ub ON au.Id = ub.UserId
LEFT OUTER JOIN PostActivity pa ON pp.Id = pa.PostId
WHERE au.UserRank <= 100
   OR EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = pp.Id AND pl.LinkTypeId = 3)
UNION ALL
SELECT NULL AS UserId, 'Summary' AS DisplayName, NULL AS UserRank, NULL AS UserLocation,
       NULL AS PostId, SUM(pp.Score) AS Score, SUM(pp.ViewCount) AS ViewCount, NULL AS FormattedTags,
       SUM(ub.BadgeCount) AS BadgeCount, SUM(ub.GoldBadges) AS GoldBadges, MAX(ub.LatestBadgeDate) AS LatestBadgeDate,
       SUM(pa.EditCount) AS EditCount, SUM(pa.PositiveComments) AS PositiveComments,
       AVG(COALESCE((SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = pp.Id AND v.VoteTypeId = 8 AND v.BountyAmount IS NOT NULL), 0)) AS AvgBounty,
       NULL AS ScoreCategory
FROM ActiveUsers au
LEFT OUTER JOIN PopularPosts pp ON au.Id = pp.OwnerUserId
LEFT OUTER JOIN UserBadges ub ON au.Id = ub.UserId
LEFT OUTER JOIN PostActivity pa ON pp.Id = pa.PostId
ORDER BY UserRank ASC NULLS LAST, Score DESC;

-- {"query": "23009.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2685, "output_tokens": 831} 
WITH ActiveUsers AS (
    SELECT u.Id, u.Reputation, u.DisplayName,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS UserRank,
           COALESCE(u.UpVotes + u.DownVotes, 0) AS TotalVotes,
           CASE WHEN u.Location IS NULL THEN 'Unknown' ELSE UPPER(u.Location) END AS NormalizedLocation
    FROM Users u
    WHERE u.Reputation > (SELECT AVG(Reputation) FROM Users WHERE Reputation > 0)
      AND EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id AND p.CreationDate > cast('2024-10-01' as date) - INTERVAL '1 year')
),
PostAnalytics AS (
    SELECT p.Id AS PostId, p.Title, p.Score, p.ViewCount,
           (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 0) AS PositiveComments,
           LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousScore,
           STRING_AGG(SUBSTRING(t.TagName, 1, 10), ', ') AS ShortTags
    FROM Posts p
    LEFT JOIN Tags t ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId = 1  -- Questions
    GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.OwnerUserId, p.CreationDate
    HAVING COUNT(DISTINCT t.Id) > 1
),
BadgeSummary AS (
    SELECT b.UserId, COUNT(b.Id) AS BadgeCount,
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
           MAX(b.Date) AS LatestBadgeDate
    FROM Badges b
    WHERE b.TagBased = TRUE
    GROUP BY b.UserId
)
SELECT au.DisplayName, au.UserRank, au.TotalVotes, au.NormalizedLocation,
       pa.Title, pa.Score, pa.ViewCount, pa.PositiveComments,
       COALESCE(pa.PreviousScore, 0) AS PrevScoreDiff,
       pa.ShortTags,
       bs.BadgeCount, bs.GoldBadges,
       (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = pa.PostId AND v.VoteTypeId = 8 AND v.BountyAmount IS NOT NULL) AS AvgBounty,
       CASE WHEN p.ClosedDate IS NULL THEN 'Open' ELSE 'Closed' END AS Status
FROM ActiveUsers au
INNER JOIN Posts p ON p.OwnerUserId = au.Id
LEFT OUTER JOIN PostAnalytics pa ON pa.PostId = p.Id
LEFT JOIN BadgeSummary bs ON bs.UserId = au.Id
LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4,5,6)  -- Edits
WHERE au.UserRank <= 100
  AND (pa.Score > 10 OR pa.PositiveComments > 5)
  AND p.CreationDate BETWEEN '2020-01-01' AND cast('2024-10-01' as date)
GROUP BY au.DisplayName, au.UserRank, au.TotalVotes, au.NormalizedLocation,
         pa.Title, pa.Score, pa.ViewCount, pa.PositiveComments, pa.PreviousScore,
         pa.ShortTags, bs.BadgeCount, bs.GoldBadges, p.ClosedDate, pa.PostId
HAVING COUNT(DISTINCT ph.Id) > 3
UNION ALL
SELECT NULL AS DisplayName, NULL AS UserRank, NULL AS TotalVotes, 'Summary' AS NormalizedLocation,
       'Total Questions' AS Title, SUM(pa.Score) AS Score, SUM(pa.ViewCount) AS ViewCount, SUM(pa.PositiveComments) AS PositiveComments,
       AVG(COALESCE(pa.PreviousScore, 0)) AS PrevScoreDiff,
       NULL AS ShortTags,
       NULL AS BadgeCount, NULL AS GoldBadges,
       NULL AS AvgBounty,
       NULL AS Status
FROM PostAnalytics pa
ORDER BY UserRank ASC, Score DESC;
-- {"query": "23042.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2685, "output_tokens": 878} 
WITH TopUsers AS (
    SELECT u.Id AS UserId, u.Reputation, u.DisplayName,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS UserRank,
           COALESCE(u.UpVotes + u.DownVotes, 0) AS TotalVotes
    FROM Users u
    WHERE u.Reputation > (SELECT AVG(Reputation) FROM Users) * 2
      AND u.Location IS NOT NULL
      AND LOWER(u.Location) LIKE '%united states%'
),
UserPosts AS (
    SELECT p.Id AS PostId, p.OwnerUserId, p.Score, p.ViewCount, p.Title,
           p.Tags,
           LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevScore,
           CASE WHEN p.AcceptedAnswerId IS NULL THEN 'No Accepted Answer' ELSE 'Has Accepted' END AS AcceptStatus,
           (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 0) AS PositiveComments
    FROM Posts p
    INNER JOIN TopUsers tu ON p.OwnerUserId = tu.UserId
    WHERE p.PostTypeId IN (1, 2)  -- Questions and Answers
      AND p.Score > 10
      AND (p.Body LIKE '%SQL%' OR p.Title LIKE '%query%')
),
UserBadges AS (
    SELECT b.UserId, COUNT(b.Id) AS BadgeCount,
           STRING_AGG(b.Name, ', ') AS BadgeNames,
           MAX(CASE WHEN b.Class = 1 THEN b.Date ELSE NULL END) AS LatestGoldBadge
    FROM Badges b
    GROUP BY b.UserId
    HAVING COUNT(b.Id) > 5
),
PostHistorySummary AS (
    SELECT ph.PostId, COUNT(ph.Id) AS EditCount,
           MIN(ph.CreationDate) AS FirstEdit,
           MAX(ph.CreationDate) AS LastEdit
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6)  -- Edits
      AND ph.Comment IS NOT NULL
    GROUP BY ph.PostId
),
CombinedData AS (
    SELECT tu.UserId, tu.DisplayName, tu.Reputation, tu.UserRank, tu.TotalVotes,
           up.PostId, up.Score, up.ViewCount, up.Title,
           COALESCE(up.PrevScore, 0) AS PrevScore,
           up.AcceptStatus,
           up.PositiveComments,
           COALESCE(ub.BadgeCount, 0) AS BadgeCount,
           ub.BadgeNames,
           ub.LatestGoldBadge,
           phs.EditCount,
           phs.FirstEdit,
           phs.LastEdit,
           CASE WHEN up.Tags IS NOT NULL THEN REPLACE(SUBSTRING(up.Tags, 2, LENGTH(up.Tags)-2), '><', ', ') ELSE 'No Tags' END AS ParsedTags,
           RANK() OVER (PARTITION BY tu.UserId ORDER BY up.Score DESC) AS PostRank
    FROM TopUsers tu
    LEFT JOIN UserPosts up ON tu.UserId = up.OwnerUserId
    LEFT JOIN UserBadges ub ON tu.UserId = ub.UserId
    LEFT JOIN PostHistorySummary phs ON up.PostId = phs.PostId
    WHERE up.Score > COALESCE(up.PrevScore, 0) OR up.PrevScore IS NULL
)
SELECT * FROM CombinedData
UNION ALL
SELECT NULL AS UserId, 'Summary' AS DisplayName, SUM(Reputation) AS Reputation, NULL AS UserRank, SUM(TotalVotes) AS TotalVotes,
       NULL AS PostId, AVG(Score) AS Score, SUM(ViewCount) AS ViewCount, NULL AS Title,
       NULL AS PrevScore,
       NULL AS AcceptStatus,
       SUM(PositiveComments) AS PositiveComments,
       SUM(BadgeCount) AS BadgeCount,
       NULL AS BadgeNames,
       MAX(LatestGoldBadge) AS LatestGoldBadge,
       SUM(EditCount) AS EditCount,
       MIN(FirstEdit) AS FirstEdit,
       MAX(LastEdit) AS LastEdit,
       NULL AS ParsedTags,
       NULL AS PostRank
FROM CombinedData
WHERE UserRank <= 10
ORDER BY UserRank ASC, PostRank ASC;
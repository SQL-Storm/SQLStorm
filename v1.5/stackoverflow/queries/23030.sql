-- {"query": "23030.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2685, "output_tokens": 864} 
WITH TopUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS UserRank
    FROM Users u
    WHERE u.Reputation > 1000
),
UserPosts AS (
    SELECT p.Id AS PostId, p.PostTypeId, p.Score, p.ViewCount, p.Title,
           tu.Id AS UserId, tu.DisplayName,
           CASE WHEN p.Tags IS NULL THEN 'No Tags' ELSE CONCAT('<', REPLACE(p.Tags, '><', '>, <'), '>') END AS FormattedTags,
           LAG(p.Score) OVER (PARTITION BY tu.Id ORDER BY p.CreationDate) AS PrevScore
    FROM Posts p
    INNER JOIN TopUsers tu ON p.OwnerUserId = tu.Id
    WHERE p.PostTypeId IN (1, 2)  -- Questions and Answers
),
PostAnalytics AS (
    SELECT up.PostId, up.UserId, up.Score, up.ViewCount,
           (SELECT COUNT(*) FROM Comments c WHERE c.PostId = up.PostId AND c.Score > 0) AS PositiveComments,
           COALESCE((SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = up.PostId AND v.VoteTypeId = 8), 0) AS AvgBounty,
           CASE WHEN up.PrevScore IS NULL THEN up.Score ELSE up.Score - up.PrevScore END AS ScoreDelta
    FROM UserPosts up
),
BadgeSummary AS (
    SELECT b.UserId, COUNT(*) AS BadgeCount,
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
           STRING_AGG(b.Name, ', ') AS BadgeNames
    FROM Badges b
    GROUP BY b.UserId
),
EditHistory AS (
    SELECT ph.PostId, COUNT(*) AS EditCount,
           MAX(ph.CreationDate) AS LastEdit
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6,7,8,9)  -- Edits and Rollbacks
    GROUP BY ph.PostId
)
SELECT DISTINCT pa.UserId, tu.DisplayName, tu.Reputation, tu.UserRank,
       COALESCE(bs.BadgeCount, 0) AS BadgeCount, COALESCE(bs.GoldBadges, 0) AS GoldBadges,
       COALESCE(bs.BadgeNames, 'No Badges') AS BadgeNames,
       SUM(pa.Score) OVER (PARTITION BY pa.UserId) AS TotalScore,
       AVG(pa.ViewCount) OVER (PARTITION BY pa.UserId) AS AvgViews,
       MAX(pa.PositiveComments) OVER (PARTITION BY pa.UserId) AS MaxComments,
       (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = pa.PostId AND pl.LinkTypeId = 3) AS DuplicateLinks,
       CASE WHEN eh.EditCount IS NULL THEN 'No Edits' ELSE CONCAT('Edited ', eh.EditCount, ' times, last on ', eh.LastEdit) END AS EditSummary,
       RANK() OVER (PARTITION BY pa.UserId ORDER BY pa.ScoreDelta DESC) AS DeltaRank
FROM PostAnalytics pa
INNER JOIN TopUsers tu ON pa.UserId = tu.Id
LEFT OUTER JOIN BadgeSummary bs ON pa.UserId = bs.UserId
LEFT OUTER JOIN EditHistory eh ON pa.PostId = eh.PostId
WHERE pa.Score > 10 OR pa.AvgBounty > 0
UNION ALL
SELECT tu.Id AS UserId, tu.DisplayName, tu.Reputation, tu.UserRank,
       COALESCE(bs.BadgeCount, 0), COALESCE(bs.GoldBadges, 0),
       COALESCE(bs.BadgeNames, 'No Badges'),
       0 AS TotalScore, 0 AS AvgViews, 0 AS MaxComments, 0 AS DuplicateLinks,
       'Inactive User' AS EditSummary, 0 AS DeltaRank
FROM TopUsers tu
LEFT OUTER JOIN BadgeSummary bs ON tu.Id = bs.UserId
WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = tu.Id)
ORDER BY Reputation DESC, UserRank;
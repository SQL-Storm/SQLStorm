WITH UserBadgeCounts AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) AS GoldBadgeCount,
        AVG(u.Reputation) OVER (PARTITION BY b.Class) AS ClassAvgReputation,
        FIRST_VALUE(b.Name) OVER (PARTITION BY u.Id ORDER BY b.Date DESC) AS LatestBadgeName
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId AND b.Class = 1
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation, b.Class, b.Date, b.Name
),
PostAnalytics AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Score,
        p.Tags,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotes,
        COALESCE(NULLIF(p.ViewCount, 0), 1) AS NormalizedViews
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    GROUP BY p.Id, p.PostTypeId, p.Score, p.Tags, p.ViewCount
)
SELECT 
    ubc.UserId,
    ubc.DisplayName,
    ubc.GoldBadgeCount,
    ubc.ClassAvgReputation,
    pa.PostTypeId,
    pa.Score,
    pa.UpVotes,
    pa.DownVotes,
    ROUND(CAST(pa.UpVotes * 100.0 / pa.NormalizedViews AS numeric), 2) AS EngagementRate,
    CASE 
        WHEN pa.Score > 10 THEN 'High Impact'
        WHEN pa.Score BETWEEN 0 AND 10 THEN 'Moderate Impact'
        ELSE 'Low Impact'
    END AS PostImpactCategory,
    COALESCE(
      NULLIF(array_length(string_to_array(replace(replace(pa.Tags, '<', ''), '>', ''), ','), 1), 0),
      0
    ) AS TagCount
FROM UserBadgeCounts ubc
JOIN PostAnalytics pa ON ubc.UserId = (
    SELECT p2.OwnerUserId FROM Posts p2 WHERE p2.Id = pa.Id
    LIMIT 1
)
WHERE ubc.GoldBadgeCount > 0
  AND pa.PostTypeId IN (1, 2)
ORDER BY EngagementRate DESC
LIMIT 100;
WITH
RecentPosts AS (
  SELECT
    p.Id,
    p.OwnerUserId,
    p.PostTypeId,
    p.CreationDate,
    ROW_NUMBER() OVER (
      PARTITION BY p.OwnerUserId
      ORDER BY p.CreationDate DESC
    ) AS rn
  FROM Posts p
  WHERE p.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30 days'
),
TopUsers AS (
  SELECT
    u.Id        AS UserId,
    u.DisplayName,
    RANK() OVER (ORDER BY u.Reputation DESC) AS RepRank,
    COALESCE(u.AboutMe, '')                 AS AboutMeText
  FROM Users u
  WHERE u.Views > 1000
),
UserPostCounts AS (
  SELECT
    OwnerUserId AS UserId,
    COUNT(*)     AS PostCount
  FROM Posts
  GROUP BY OwnerUserId
),
TagPosts AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagUsage
  FROM Posts p,
    LATERAL (
      SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS TagName
    ) t
  GROUP BY t.TagName
),
BadgeUnion AS (
  SELECT Name, 'Gold'   AS Tier, UserId, Date FROM Badges WHERE Class = 1
  UNION ALL
  SELECT Name, 'Silver' AS Tier, UserId, Date FROM Badges WHERE Class = 2
  UNION ALL
  SELECT Name, 'Bronze' AS Tier, UserId, Date FROM Badges WHERE Class = 3
),
RecentBadge AS (
  SELECT DISTINCT ON (UserId)
    UserId,
    Name   AS LatestBadge
  FROM BadgeUnion
  ORDER BY UserId, Date DESC
),
FilteredUsers AS (
  SELECT
    tu.UserId,
    tu.DisplayName,
    COALESCE(up.PostCount,0) AS PostCount,
    tu.RepRank,
    rb.LatestBadge
  FROM TopUsers tu
  LEFT JOIN UserPostCounts up ON up.UserId = tu.UserId
  LEFT JOIN RecentBadge rb      ON rb.UserId = tu.UserId
  WHERE tu.RepRank <= 100
    AND (up.PostCount > 10 OR up.PostCount IS NULL)
),
MainResult AS (
  SELECT
    fu.UserId,
    fu.DisplayName,
    fu.PostCount,
    fu.RepRank,
    COUNT(rp.Id) OVER (PARTITION BY fu.UserId)      AS RecentPostCount,
    MAX(tp.TagUsage) OVER (PARTITION BY fu.UserId)   AS MaxTagUsage,
    CASE WHEN fu.PostCount = 0 THEN 'NoPosts' ELSE 'Active' END AS ActivityStatus,
    (SELECT COUNT(*)
     FROM Comments c
     WHERE c.UserId = fu.UserId
       AND c.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '60 days'
    ) AS RecentComments
  FROM FilteredUsers fu
  FULL OUTER JOIN RecentPosts rp
    ON rp.OwnerUserId = fu.UserId AND rp.rn <= 5
  LEFT JOIN TagPosts tp
    ON tp.TagName = fu.LatestBadge
  WHERE EXISTS (
    SELECT 1
    FROM Posts p2
    WHERE p2.OwnerUserId = fu.UserId
      AND p2.Score > COALESCE(
        (SELECT AVG(p3.Score) FROM Posts p3 WHERE p3.OwnerUserId = p2.OwnerUserId)
      ,0)
  )
    AND fu.DisplayName ~ '^[A-Za-z]'
),
PostFilter AS (
  SELECT
    p.OwnerUserId                 AS UserId,
    CAST(NULL AS VARCHAR)         AS DisplayName,
    COUNT(*)                      AS PostCount,
    0                             AS RepRank,
    MAX(p.ViewCount)              AS RecentPostCount,
    CASE WHEN MAX(p.Score) > 0 THEN 'HighScore' ELSE 'LowScore' END AS ActivityStatus,
    MAX(p.Score)                  AS MaxTagUsage
  FROM Posts p
  WHERE p.ViewCount > 10000
  GROUP BY p.OwnerUserId
),
VoteFilter AS (
  SELECT
    v.UserId,
    CAST(NULL AS VARCHAR)  AS DisplayName,
    0                      AS PostCount,
    0                      AS RepRank,
    0                      AS RecentPostCount,
    'VotedDown'            AS ActivityStatus,
    0                      AS MaxTagUsage
  FROM Votes v
  WHERE v.VoteTypeId = 3
),
-- Normalize column list for set operations to avoid mismatched column counts
MR AS (
  SELECT
    UserId,
    DisplayName,
    PostCount,
    RepRank,
    RecentPostCount,
    ActivityStatus,
    MaxTagUsage
  FROM MainResult
),
PF AS (
  SELECT
    UserId,
    DisplayName,
    PostCount,
    RepRank,
    RecentPostCount,
    ActivityStatus,
    MaxTagUsage
  FROM PostFilter
),
VF AS (
  SELECT
    UserId,
    DisplayName,
    PostCount,
    RepRank,
    RecentPostCount,
    ActivityStatus,
    MaxTagUsage
  FROM VoteFilter
),
-- Emulate INTERSECT and EXCEPT in a dialect-agnostic way using joins and distinct
Intersected AS (
  SELECT DISTINCT m.*
  FROM MR m
  INNER JOIN PF p
    ON m.UserId = p.UserId
    AND ( (m.DisplayName IS NOT DISTINCT FROM p.DisplayName) OR (m.DisplayName IS NULL AND p.DisplayName IS NULL) )
    AND COALESCE(m.PostCount,0) = COALESCE(p.PostCount,0)
    AND COALESCE(m.RepRank,0) = COALESCE(p.RepRank,0)
    AND COALESCE(m.RecentPostCount,0) = COALESCE(p.RecentPostCount,0)
    AND COALESCE(m.ActivityStatus,'') = COALESCE(p.ActivityStatus,'')
    AND COALESCE(m.MaxTagUsage,0) = COALESCE(p.MaxTagUsage,0)
),
FinalSet AS (
  SELECT i.*
  FROM Intersected i
  LEFT JOIN VF v
    ON i.UserId = v.UserId
    AND ( (i.DisplayName IS NOT DISTINCT FROM v.DisplayName) OR (i.DisplayName IS NULL AND v.DisplayName IS NULL) )
    AND COALESCE(i.PostCount,0) = COALESCE(v.PostCount,0)
    AND COALESCE(i.RepRank,0) = COALESCE(v.RepRank,0)
    AND COALESCE(i.RecentPostCount,0) = COALESCE(v.RecentPostCount,0)
    AND COALESCE(i.ActivityStatus,'') = COALESCE(v.ActivityStatus,'')
    AND COALESCE(i.MaxTagUsage,0) = COALESCE(v.MaxTagUsage,0)
  WHERE v.UserId IS NULL
)
SELECT
  UserId,
  DisplayName,
  PostCount,
  RepRank,
  RecentPostCount,
  ActivityStatus,
  MaxTagUsage
FROM FinalSet
ORDER BY UserId;
WITH
RecentActivity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    ROW_NUMBER() OVER (
      PARTITION BY p.OwnerUserId
      ORDER BY p.LastActivityDate DESC, p.Score DESC, p.ViewCount DESC
    ) AS rn_owner
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.LastActivityDate IS NOT NULL
),
UserBadgeStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(b.Id) AS BadgeCount,
    MAX(b.Date) AS LastBadgeDate,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
PostMetrics AS (
  SELECT
    ra.PostId,
    ra.Title,
    ra.CreationDate,
    ra.LastActivityDate,
    ra.Score,
    ra.ViewCount,
    ra.OwnerUserId,
    ra.Tags,
    u.Id AS UserId,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    b.BadgeCount,
    b.LastBadgeDate,
    b.GoldBadges,
    COALESCE(ra.Score, 0) * 0.7
      + COALESCE(ra.ViewCount, 0) * 0.2
      + COALESCE(b.GoldBadges, 0) * 1.5
      + (CASE WHEN ra.LastActivityDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '180' DAY) THEN 2 ELSE 0 END) AS PerformanceIndex
  FROM RecentActivity ra
  LEFT JOIN Users u ON u.Id = ra.OwnerUserId
  LEFT JOIN UserBadgeStats b ON b.UserId = u.Id
),
TopPosts AS (
  SELECT
    pm.PostId,
    pm.Title,
    pm.CreationDate,
    pm.LastActivityDate,
    pm.Score,
    pm.ViewCount,
    pm.OwnerUserId,
    pm.Tags,
    pm.UserId,
    pm.OwnerDisplayName,
    pm.OwnerReputation,
    pm.BadgeCount,
    pm.LastBadgeDate,
    pm.GoldBadges,
    pm.PerformanceIndex,
    NTILE(5) OVER (ORDER BY pm.PerformanceIndex DESC) AS Quintile
  FROM PostMetrics pm
  WHERE pm.ViewCount > 0
    AND pm.Score IS NOT NULL
    AND pm.OwnerReputation > 0
)
SELECT
  tp.PostId,
  tp.Title,
  tp.OwnerDisplayName,
  tp.OwnerReputation,
  tp.ViewCount,
  tp.Score,
  tp.LastActivityDate,
  tp.Tags,
  tp.Quintile,
  CASE
    WHEN tp.Quintile = 1 THEN 'Top-20%'
    WHEN tp.Quintile = 2 THEN 'Next-20%'
    WHEN tp.Quintile = 3 THEN 'Mid-20%'
    WHEN tp.Quintile = 4 THEN 'Bottom-20%'
    ELSE 'Bottom-20+'
  END AS Segment,
  CONCAT('[', tp.PostId, '] ', COALESCE(tp.Title, ''), ' by ', COALESCE(tp.OwnerDisplayName, 'Unknown')) AS Signature,
  (SELECT COUNT(*)
     FROM PostLinks pl
     WHERE pl.PostId = tp.PostId
       AND pl.RelatedPostId IS NOT NULL
       AND EXISTS (
         SELECT 1
         FROM LinkTypes lt
         WHERE lt.Id = pl.LinkTypeId
           AND LOWER(lt.Name) LIKE LOWER('%Duplicate%')
       )
  ) AS DuplicateRelatedLinks,
  EXISTS (
    SELECT 1
    FROM Comments c
    WHERE c.PostId = tp.PostId
      AND (c.UserId IS NULL OR c.UserId = 0)
  ) AS HasNullUserComment
FROM TopPosts tp
ORDER BY tp.PerformanceIndex DESC, tp.LastActivityDate DESC
LIMIT 100;
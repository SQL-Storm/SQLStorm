WITH
RecentActivity AS (
  SELECT
    ph.UserId,
    MAX(ph.CreationDate) AS LastActivityDate,
    COUNT(*) AS HistoryCount
  FROM PostHistory ph
  WHERE ph.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '90 days'
  GROUP BY ph.UserId
),
UserBadgeScore AS (
  SELECT
    u.Id AS UserId,
    u.Reputation,
    COALESCE(SUM(CASE WHEN b.Class = 1 THEN 100 ELSE 0 END), 0) AS GoldScore,
    COALESCE(SUM(CASE WHEN b.Class = 2 THEN 50 ELSE 0 END), 0) AS SilverScore,
    COALESCE(SUM(CASE WHEN b.Class = 3 THEN 25 ELSE 0 END), 0) AS BronzeScore,
    -- treat TagBased as boolean-like: compare to TRUE or to numeric 1 after casting if needed
    COALESCE(SUM(CASE WHEN (b.TagBased = TRUE OR CAST(b.TagBased AS INTEGER) = 1) THEN 10 ELSE 0 END), 0) AS TagBadgeScore
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id, u.Reputation
),
PostMetrics AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.ViewCount,
    p.Score,
    p.CreationDate,
    p.LastActivityDate,
    p.Tags,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.ViewCount DESC, p.Score DESC, p.CreationDate DESC) AS RN
  FROM Posts p
  WHERE p.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '365 days'
    AND (p.PostTypeId = 1 OR p.PostTypeId = 2)
),
TagRelations AS (
  SELECT
    t.TagName,
    t.ExcerptPostId,
    t.WikiPostId
  FROM Tags t
  WHERE t.Count > 100
),
DuplicateLinks AS (
  SELECT
    pl.PostId,
    COUNT(*) AS DuplicateCount
  FROM PostLinks pl
  JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
  WHERE lt.Name IN ('Duplicate')
  GROUP BY pl.PostId
)
SELECT
  u.Id AS UserId,
  u.DisplayName AS UserName,
  ra.LastActivityDate,
  ra.HistoryCount,
  u.Reputation,
  (ub.GoldScore + ub.SilverScore + ub.BronzeScore + ub.TagBadgeScore) AS BadgeImpact,
  pm.PostId,
  pm.Title,
  pm.ViewCount,
  pm.Score,
  pm.CreationDate,
  pm.LastActivityDate AS PostLastActivityDate,
  pm.RN,
  COALESCE(dl.DuplicateCount, 0) AS DuplicateCount,
  tg.TagName
FROM Users u
LEFT JOIN RecentActivity ra ON ra.UserId = u.Id
LEFT JOIN UserBadgeScore ub ON ub.UserId = u.Id
LEFT JOIN PostMetrics pm ON pm.OwnerUserId = u.Id AND pm.RN = 1
LEFT JOIN DuplicateLinks dl ON dl.PostId = pm.PostId
LEFT JOIN LATERAL (
  SELECT tg_inner.TagName
  FROM TagRelations tr
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(SUBSTRING(pm.Tags FROM 2 FOR CHAR_LENGTH(pm.Tags)-2), '><')) AS TagName
  ) AS tg_inner
  WHERE tr.ExcerptPostId = pm.PostId OR tr.WikiPostId = pm.PostId
  ORDER BY tg_inner.TagName
  LIMIT 1
) AS tg ON TRUE
WHERE u.AccountId IS NOT NULL
  AND (u.Reputation > 1000 OR COALESCE(ra.HistoryCount, 0) > 20)
GROUP BY
  u.Id,
  u.DisplayName,
  ra.LastActivityDate,
  ra.HistoryCount,
  u.Reputation,
  ub.GoldScore,
  ub.SilverScore,
  ub.BronzeScore,
  ub.TagBadgeScore,
  pm.PostId,
  pm.Title,
  pm.ViewCount,
  pm.Score,
  pm.CreationDate,
  pm.LastActivityDate,
  pm.RN,
  dl.DuplicateCount,
  tg.TagName
ORDER BY BadgeImpact DESC, pm.Score DESC, pm.ViewCount DESC
LIMIT 100;
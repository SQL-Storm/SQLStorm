WITH PostWindow AS (
  SELECT p.Id,
         p.Title,
         p.ViewCount,
         p.Score,
         p.CreationDate,
         p.OwnerUserId,
         ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC, p.Score DESC NULLS LAST) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1
),
LastAct AS (
  SELECT p.Id AS PostId, MAX(p.LastActivityDate) AS LastActivity
  FROM Posts p
  GROUP BY p.Id
),
GoldBadges AS (
  SELECT b.UserId, COUNT(*) AS GoldCount
  FROM Badges b
  WHERE b.Class = 1
  GROUP BY b.UserId
),
LinkCount AS (
  SELECT pl.PostId, COUNT(*) AS LinkCount
  FROM PostLinks pl
  GROUP BY pl.PostId
),
AvgUserBounty AS (
  SELECT v.UserId, AVG(COALESCE(v.BountyAmount, 0)) AS AvgBounty
  FROM Votes v
  GROUP BY v.UserId
),
PostTagStats AS (
  SELECT t.TagName, COUNT(*) AS TagUsage
  FROM Tags t
  GROUP BY t.TagName
),
PostOwnerAgg AS (
  SELECT u.Id AS UserId, AVG(COALESCE(v.BountyAmount, 0)) AS UserAvgBounty
  FROM Users u
  LEFT JOIN Votes v ON v.UserId = u.Id
  GROUP BY u.Id
)
SELECT
  pw.Id,
  pw.Title,
  pw.ViewCount,
  pw.Score,
  pw.CreationDate,
  u.DisplayName AS OwnerDisplayName,
  COALESCE(gb.GoldCount, 0) AS GoldBadges,
  COALESCE(lc.LinkCount, 0) AS LinkedPostCount,
  COALESCE(la.LastActivity, pw.CreationDate) AS LastActivityDate,
  COALESCE(ou.UserAvgBounty, 0) AS AvgBountyGivenByOwner,
  COALESCE(av.AvgBounty, 0) AS AvgBountyForOwner
FROM PostWindow pw
JOIN Users u ON pw.OwnerUserId = u.Id
LEFT JOIN GoldBadges gb ON gb.UserId = u.Id
LEFT JOIN LinkCount lc ON lc.PostId = pw.Id
LEFT JOIN LastAct la ON la.PostId = pw.Id
LEFT JOIN PostOwnerAgg ou ON ou.UserId = u.Id
LEFT JOIN AvgUserBounty av ON av.UserId = u.Id
WHERE pw.rn = 1

UNION ALL

SELECT
  pw.Id,
  pw.Title,
  pw.ViewCount,
  pw.Score,
  pw.CreationDate,
  u.DisplayName AS OwnerDisplayName,
  COALESCE(gb.GoldCount, 0) AS GoldBadges,
  COALESCE(lc.LinkCount, 0) AS LinkedPostCount,
  COALESCE(la.LastActivity, pw.CreationDate) AS LastActivityDate,
  COALESCE(ou.UserAvgBounty, 0) AS AvgBountyGivenByOwner,
  COALESCE(av.AvgBounty, 0) AS AvgBountyForOwner
FROM PostWindow pw
JOIN Users u ON pw.OwnerUserId = u.Id
LEFT JOIN GoldBadges gb ON gb.UserId = u.Id
LEFT JOIN LinkCount lc ON lc.PostId = pw.Id
LEFT JOIN LastAct la ON la.PostId = pw.Id
LEFT JOIN PostOwnerAgg ou ON ou.UserId = u.Id
LEFT JOIN AvgUserBounty av ON av.UserId = u.Id
WHERE pw.rn = 2

ORDER BY LastActivityDate DESC, ViewCount DESC;
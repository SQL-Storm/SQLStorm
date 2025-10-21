SELECT
  u.Id AS UserId,
  u.DisplayName,
  COUNT(DISTINCT p.Id) AS PostCount,
  SUM(p.ViewCount) AS TotalViews,
  AVG(p.Score) AS AvgScore,
  MAX(p.CreationDate) AS LastPostDate,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
  COALESCE(SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END), 0) AS GoldBadges,
  COALESCE(SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END), 0) AS SilverBadges,
  COALESCE(SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END), 0) AS BronzeBadges
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
WHERE
  u.Id IS NOT NULL
  AND u.Reputation > 1000
  AND p.CreationDate IS NOT NULL
GROUP BY
  u.Id, u.DisplayName
HAVING
  COUNT(DISTINCT p.Id) > 10
ORDER BY
  TotalViews DESC, PostCount DESC
LIMIT 100;
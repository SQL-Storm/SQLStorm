SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  COUNT(DISTINCT p.Id) AS PostCount,
  AVG(p.Score) AS AvgPostScore,
  SUM(COALESCE(p.ViewCount, 0)) AS TotalViews,
  MAX(p.CreationDate) AS LatestPostDate,
  STRING_AGG(DISTINCT t.Name, ',') AS TagsUsed
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN LATERAL (
    SELECT unnest(string_to_array(p.Tags, '><')) AS Name
  ) AS t ON TRUE
GROUP BY
  u.Id,
  u.DisplayName,
  u.Reputation
ORDER BY
  TotalViews DESC,
  AvgPostScore DESC
LIMIT 100;
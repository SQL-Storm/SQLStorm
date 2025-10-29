-- {"query": "5262.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 344}
SELECT
  u.Id AS UserId,
  u.DisplayName AS UserName,
  COUNT(DISTINCT p.Id) AS PostCount,
  SUM(p.Score) AS TotalScore,
  AVG(p.ViewCount) AS AvgViewsPerPost,
  MAX(p.LastActivityDate) AS LastActivePostDate,
  STRING_AGG(DISTINCT tt.Name, ',') AS PostTypesEncountered,
  CAST(COALESCE(b.TotalGold, 0) AS INTEGER) AS GoldBadges,
  CAST(COALESCE(b.TotalSilver, 0) AS INTEGER) AS SilverBadges,
  CAST(COALESCE(b.TotalBronze, 0) AS INTEGER) AS BronzeBadges
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT
      b.UserId,
      SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS TotalGold,
      SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS TotalSilver,
      SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS TotalBronze
    FROM Badges b
    GROUP BY b.UserId
  ) b ON b.UserId = u.Id
  LEFT JOIN PostTypes tt ON p.PostTypeId = tt.Id
WHERE
  u.AccountId IS NOT NULL
GROUP BY
  u.Id,
  u.DisplayName,
  b.TotalGold,
  b.TotalSilver,
  b.TotalBronze
HAVING
  COUNT(DISTINCT p.Id) > 0
ORDER BY
  TotalScore DESC NULLS LAST,
  PostCount DESC
LIMIT 100;
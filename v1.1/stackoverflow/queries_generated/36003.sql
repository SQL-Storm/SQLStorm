-- {"query": "36003.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 282} 
SELECT
  u.Id AS UserId,
  u.DisplayName,
  COUNT(DISTINCT p.Id) AS PostCount,
  SUM(p.ViewCount) AS TotalViews,
  AVG(p.Score) AS AvgScore,
  MAX(p.CreationDate) AS LastPostDate,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
  COALESCE(SUM(b.Class = 1::int), 0) AS GoldBadges,
  COALESCE(SUM(b.Class = 2::int), 0) AS SilverBadges,
  COALESCE(SUM(b.Class = 3::int), 0) AS BronzeBadges
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
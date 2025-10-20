-- {"query": "36019.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 305} 
SELECT
  u.Id AS UserId,
  u.DisplayName,
  COUNT(DISTINCT p.Id) AS TotalPosts,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
  AVG(p.Score) AS AvgPostScore,
  SUM(p.ViewCount) AS TotalViews,
  MAX(p.CreationDate) AS MostRecentPostDate,
  COUNT(DISTINCT b.Id) AS BadgesEarned,
  SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
  SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
  SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
FROM
  Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN Badges b ON b.UserId = u.Id
WHERE
  u.Id IN (
    SELECT DISTINCT OwnerUserId
    FROM Posts
    WHERE OwnerUserId IS NOT NULL
  )
  AND u.CreationDate >= NOW() - INTERVAL '2 years'
GROUP BY
  u.Id, u.DisplayName
ORDER BY
  TotalPosts DESC, GoldBadges DESC, TotalViews DESC
LIMIT 100;
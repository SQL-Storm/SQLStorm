WITH OwnerStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
    COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
    COALESCE(SUM(p.Score), 0) AS TotalPostScore,
    AVG(CASE WHEN p.PostTypeId IN (1,2) THEN p.Score ELSE NULL END) AS AvgPostScore,
    COALESCE(SUM(p.ViewCount), 0) AS SumViewCounts,
    COUNT(CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
    COUNT(CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
    COUNT(CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  WHERE u.DisplayName IS NOT NULL
  GROUP BY u.Id, u.DisplayName, u.Reputation
)
SELECT
  UserId,
  DisplayName,
  Reputation,
  TotalQuestions,
  TotalAnswers,
  TotalPostScore,
  AvgPostScore,
  SumViewCounts,
  GoldBadges,
  SilverBadges,
  BronzeBadges
FROM OwnerStats;
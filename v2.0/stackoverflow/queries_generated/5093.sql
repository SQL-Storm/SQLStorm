-- {"query": "5093.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 629} 
SELECT
  u.Id AS UserId,
  u.DisplayName AS UserName,
  du.TotalDelv AS DeliveredViews,
  ru.TotalUpvotes AS UpvotesReceived,
  COALESCE(bg.BadgeGoldCount, 0) AS GoldBadges,
  COALESCE(bs.BadgeSilverCount, 0) AS SilverBadges,
  COALESCE(br.BadgeBronzeCount, 0) AS BronzeBadges,
  COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
  AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScore,
  STRING_AGG(DISTINCT t.Name, ',') AS TopTags,
  MAX(p.LastActivityDate) AS LastActive,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesGiven,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesGiven
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN LATERAL (
      SELECT
        COUNT(*) AS TotalDelv
      FROM Posts pp
      WHERE pp.OwnerUserId = u.Id
        AND pp.ViewCount > 0
    ) du ON true
  LEFT JOIN LATERAL (
      SELECT
        SUM(CASE WHEN v2.VoteTypeId = 1 THEN 1 ELSE 0 END) AS TotalUpvotes
      FROM Votes v2
      WHERE v2.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id)
    ) ru ON true
  LEFT JOIN (
      SELECT UserId,
             SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS BadgeGoldCount
      FROM Badges
      GROUP BY UserId
  ) bg ON bg.UserId = u.Id
  LEFT JOIN (
      SELECT UserId,
             SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS BadgeSilverCount
      FROM Badges
      GROUP BY UserId
  ) bs ON bs.UserId = u.Id
  LEFT JOIN (
      SELECT UserId,
             SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BadgeBronzeCount
      FROM Badges
      GROUP BY UserId
  ) br ON br.UserId = u.Id
  LEFT JOIN (
      SELECT DISTINCT TagName
      FROM Tags t
      JOIN Posts p2 ON t.WikiPostId = p2.Id
      WHERE p2.OwnerUserId = u.Id
  ) t ON true
GROUP BY
  u.Id, u.DisplayName, du.TotalDelv, ru.TotalUpvotes, bg.BadgeGoldCount, bs.BadgeSilverCount, br.BadgeBronzeCount
ORDER BY
  LastActive DESC
LIMIT 100;
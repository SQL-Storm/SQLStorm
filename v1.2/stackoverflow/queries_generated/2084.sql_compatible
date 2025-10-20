WITH RecursiveBadgeSummary AS (
  SELECT UserId,
         COUNT(*) FILTER (WHERE Class = 1) AS GoldBadges,
         COUNT(*) FILTER (WHERE Class = 2) AS SilverBadges,
         COUNT(*) FILTER (WHERE Class = 3) AS BronzeBadges
  FROM Badges
  GROUP BY UserId
), LatestAnswers AS (
  SELECT p.Id, p.ParentId, p.CreationDate, p.Score,
         u.Id AS UserId, u.DisplayName,
         ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS AnsRank
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 2
), UserAggregates AS (
  SELECT u.Id, u.DisplayName, u.Reputation,
         rs.GoldBadges, rs.SilverBadges, rs.BronzeBadges
  FROM Users u
  LEFT JOIN RecursiveBadgeSummary rs ON rs.UserId = u.Id
)
SELECT ua.Id, ua.DisplayName, ua.Reputation,
       COALESCE(ua.GoldBadges, 0) AS GoldBadges,
       COALESCE(ua.SilverBadges, 0) AS SilverBadges,
       COALESCE(ua.BronzeBadges, 0) AS BronzeBadges,
       la.Id AS AnswerId, la.ParentId AS QuestionId, la.CreationDate, la.Score, la.AnsRank
FROM UserAggregates ua
LEFT JOIN LatestAnswers la ON la.UserId = ua.Id
WHERE la.AnsRank = 1 OR la.AnsRank IS NULL
GROUP BY ua.Id, ua.DisplayName, ua.Reputation,
         ua.GoldBadges, ua.SilverBadges, ua.BronzeBadges,
         la.Id, la.ParentId, la.CreationDate, la.Score, la.AnsRank
ORDER BY ua.Reputation DESC, ua.Id;
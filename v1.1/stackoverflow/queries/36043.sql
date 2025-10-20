SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  COUNT(DISTINCT p.Id) AS PostCount,
  SUM(p.Score) AS TotalScore,
  AVG(p.Score) AS AvgScorePerPost,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
  MAX(p.CreationDate) AS LastActiveDate,
  COUNT(DISTINCT v.Id) AS VoteCount,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven,
  SUM(CASE WHEN b.Id IS NOT NULL THEN 1 ELSE 0 END) AS BadgesEarned,
  STRING_AGG(DISTINCT b.Name, ',') AS BadgeNames,
  SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
  SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
  SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id AND v.UserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
GROUP BY
  u.Id, u.DisplayName, u.Reputation
HAVING
  COUNT(DISTINCT p.Id) > 0
ORDER BY
  TotalScore DESC, PostCount DESC
LIMIT 100;
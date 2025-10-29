-- {"query": "5778.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 416} 
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  COUNT(DISTINCT p.Id) AS PostCount,
  AVG(p.Score) AS AvgPostScore,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesGiven,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesGiven,
  MAX(u.CreationDate) AS LastActive,
  STRING_AGG(DISTINCT t.Name, ',') FILTER (WHERE t.Name IS NOT NULL) AS TagsInteracted,
  COALESCE(b.BadgeCount, 0) AS GoldBadges,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
FROM Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON v.UserId = u.Id
LEFT JOIN (
  SELECT UserId, COUNT(*) AS BadgeCount
  FROM Badges
  WHERE Class = 1
  GROUP BY UserId
) b ON b.UserId = u.Id
LEFT JOIN LATERAL (
  SELECT DISTINCT t.Name
  FROM Posts pp
  JOIN PostLinks pl ON pl.PostId = pp.Id
  JOIN Tags t ON t.Id = pp.Id  -- attempt to trace tag interactions via posts; placeholder association
  WHERE pp.OwnerUserId = u.Id
  LIMIT 5
) AS t ON TRUE
WHERE u.AccountId IS NOT NULL
  AND u.Reputation > 100
GROUP BY
  u.Id,
  u.DisplayName,
  u.Reputation,
  b.BadgeCount
HAVING COUNT(DISTINCT p.Id) > 0
ORDER BY
  Reputation DESC,
  LastActive DESC
LIMIT 100;
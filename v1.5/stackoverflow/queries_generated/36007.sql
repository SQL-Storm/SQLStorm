-- {"query": "36007.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 326} 
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  COUNT(DISTINCT p.Id) AS PostCount,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived,
  AVG(p.Score) AS AvgPostScore,
  MAX(p.CreationDate) AS LastActivePostDate,
  COUNT(DISTINCT b.Id) AS BadgesEarned,
  SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
  SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
  SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id AND v.UserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  LEFT JOIN PostHistory ph ON ph.UserId = u.Id
WHERE
  u.Reputation > 1000
  AND u.CreationDate < (CURRENT_DATE - INTERVAL '2 years')
GROUP BY
  u.Id, u.DisplayName, u.Reputation
ORDER BY
  UpvotesReceived DESC, u.Reputation DESC
LIMIT 100;
-- {"query": "36002.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 291} 
SELECT
  u.Id AS UserId,
  u.DisplayName,
  COUNT(DISTINCT p.Id) AS TotalPosts,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven,
  SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
  SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
  SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
  AVG(COALESCE(p.Score, 0)) AS AvgPostScore,
  MAX(p.LastActivityDate) AS LastActiveDate
FROM
  Users u
LEFT JOIN
  Posts p ON p.OwnerUserId = u.Id
LEFT JOIN
  Votes v ON v.PostId = p.Id AND v.UserId = u.Id
LEFT JOIN
  Badges b ON b.UserId = u.Id
GROUP BY
  u.Id, u.DisplayName
ORDER BY
  TotalPosts DESC, GoldBadges DESC
LIMIT 100;
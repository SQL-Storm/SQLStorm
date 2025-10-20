-- {"query": "36054.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 363} 
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  COUNT(DISTINCT p.Id) AS TotalPosts,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
  AVG(p.Score) AS AveragePostScore,
  AVG(p.ViewCount) AS AverageViewCount,
  MAX(p.CreationDate) AS MostRecentPostDate,
  SUM(CASE WHEN v.VoteTypeId = vt.Id THEN 1 ELSE 0 END) AS UpvotesCast,
  SUM(CASE WHEN v.VoteTypeId = (SELECT Id FROM VoteTypes vt WHERE vt.Name = 'UpMod') THEN 1 ELSE 0 END) AS UpModVotes,
  SUM(CASE WHEN v.VoteTypeId = (SELECT Id FROM VoteTypes vt WHERE vt.Name = 'DownMod') THEN 1 ELSE 0 END) AS DownModVotes,
  SUM(CASE WHEN b.Id IS NOT NULL THEN 1 ELSE 0 END) AS BadgesEarned
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.UserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  CROSS JOIN (SELECT Id, Name FROM VoteTypes) vt
WHERE
  u.Id IS NOT NULL
GROUP BY
  u.Id, u.DisplayName, u.Reputation
HAVING
  COUNT(DISTINCT p.Id) > 10
ORDER BY
  TotalPosts DESC, u.Reputation DESC
LIMIT 100;
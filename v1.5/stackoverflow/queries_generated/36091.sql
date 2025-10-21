-- {"query": "36091.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 313} 
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  COUNT(p.Id) AS TotalPosts,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
  AVG(p.Score) AS AvgPostScore,
  SUM(v.BountyAmount) AS TotalBountiesEarned,
  MAX(p.CreationDate) AS LastPostDate,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesCast,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesCast,
  SUM(CASE WHEN v.VoteTypeId = 6 THEN 1 ELSE 0 END) AS CloseVotesCast,
  COUNT(DISTINCT c.Id) AS CommentCount,
  MAX(u.LastAccessDate) AS LastActive
FROM
  Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON v.PostId = p.Id AND v.UserId = u.Id
LEFT JOIN Comments c ON c.PostId = p.Id
GROUP BY
  u.Id, u.DisplayName, u.Reputation
HAVING
  COUNT(p.Id) > 0
ORDER BY
  LastPostDate DESC, TotalPosts DESC
LIMIT 100;
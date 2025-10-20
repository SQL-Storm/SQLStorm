-- {"query": "36028.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 304} 
SELECT
  u.Id AS UserId,
  u.DisplayName,
  COUNT(DISTINCT p.Id) AS TotalPosts,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
  AVG(p.Score) AS AvgPostScore,
  MAX(p.CreationDate) AS LastActive,
  COUNT(DISTINCT b.Id) AS BadgeCount,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven,
  SUM(CASE WHEN v.VoteTypeId = 10 THEN 1 ELSE 0 END) AS Deletions
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id AND v.UserId = u.Id
WHERE
  u.CreationDate >= NOW() - INTERVAL '5 years'
GROUP BY
  u.Id, u.DisplayName
HAVING
  COUNT(DISTINCT p.Id) > 0
ORDER BY
  TotalPosts DESC, LastActive DESC
LIMIT 100;
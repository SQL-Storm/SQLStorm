-- {"query": "36084.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 258} 
SELECT
  u.Id AS UserId,
  u.DisplayName AS UserName,
  COUNT(DISTINCT p.Id) AS TotalPosts,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
  SUM(v.BountyAmount) AS TotalBountiesEarned,
  AVG(p.Score) AS AvgPostScore,
  MAX(p.CreationDate) AS LastPostDate,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesCast,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesCast
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
WHERE
  u.CreationDate >= '2015-01-01'
  AND u.AccountId IS NOT NULL
GROUP BY
  u.Id, u.DisplayName
ORDER BY
  TotalPosts DESC, LastPostDate DESC
LIMIT 100;
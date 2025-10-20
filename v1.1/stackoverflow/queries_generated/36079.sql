-- {"query": "36079.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 269} 
SELECT
  u.Id AS UserId,
  u.DisplayName AS UserName,
  COUNT(p.Id) AS TotalPosts,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
  AVG(u.Reputation) AS AvgReputation,
  SUM(CASE WHEN v.VoteTypeId IN (2) THEN 1 ELSE 0 END) AS UpVotesReceived,
  SUM(CASE WHEN v.VoteTypeId IN (3) THEN 1 ELSE 0 END) AS DownVotesReceived,
  MAX(p.CreationDate) AS LastActivePostDate,
  SUM(CASE WHEN c.Id IS NOT NULL THEN 1 ELSE 0 END) AS CommentCount
FROM
  Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON v.PostId = p.Id
LEFT JOIN Comments c ON c.PostId = p.Id
WHERE
  u.CreationDate >= NOW() - INTERVAL '2 years'
GROUP BY
  u.Id, u.DisplayName
ORDER BY
  TotalPosts DESC, LastActivePostDate DESC
LIMIT 100;
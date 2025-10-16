-- {"query": "6099.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 312} 
SELECT
  u.Id AS UserId,
  u.DisplayName AS UserName,
  COUNT(DISTINCT p.Id) AS TotalPosts,
  AVG(COALESCE(p.Score,0)) AS AvgPostScore,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
  MAX(p.CreationDate) AS LastActivePostDate,
  MAX(p.LastActivityDate) AS LastActivityDate
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN PostHistory ph ON ph.PostId = p.Id
WHERE
  u.Reputation > 1000
  AND (p.PostTypeId IN (1,2) OR p.Id IS NULL)
  AND (ph.Id IS NULL OR ph.PostId = p.Id)
GROUP BY
  u.Id, u.DisplayName
HAVING
  COUNT(DISTINCT p.Id) > 5
ORDER BY
  TotalPosts DESC, AvgPostScore DESC
LIMIT 100;
-- {"query": "36001.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 266} 
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  COUNT(DISTINCT p.Id) AS TotalPosts,
  AVG(p.Score) AS AvgPostScore,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
  MIN(p.CreationDate) AS FirstPostDate,
  MAX(p.LastActivityDate) AS MostRecentActivity
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
WHERE
  u.Reputation > 1000
  AND u.CreationDate < NOW() - INTERVAL '1 year'
GROUP BY
  u.Id, u.DisplayName, u.Reputation
ORDER BY
  TotalPosts DESC,
  AvgPostScore DESC
LIMIT 100;
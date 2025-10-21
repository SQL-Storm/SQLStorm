-- {"query": "36014.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 252} 
SELECT
  u.Id AS UserId,
  u.DisplayName AS UserName,
  u.Reputation,
  COUNT(DISTINCT p.Id) AS PostCount,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
  AVG(COALESCE(p.Score,0)) AS AvgPostScore,
  MAX(p.LastActivityDate) AS LastActivePostDate,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
WHERE
  u.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '2 years'
GROUP BY
  u.Id, u.DisplayName, u.Reputation
ORDER BY
  Reputation DESC, LastActivePostDate DESC
LIMIT 100;
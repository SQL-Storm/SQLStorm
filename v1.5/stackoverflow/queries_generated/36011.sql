-- {"query": "36011.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 267} 
SELECT
  u.Id AS UserId,
  u.DisplayName,
  COUNT(p.Id) AS PostCount,
  AVG(p.Score) AS AvgPostScore,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived,
  MAX(p.CreationDate) AS LastPostDate,
  MAX(v.CreationDate) AS LastVoteDate,
  COUNT(DISTINCT bl.PostId) AS BadgesEarned,
  AVG(DATEDIFF(day, u.CreationDate, CURRENT_TIMESTAMP)) AS AverageAccountAgeDays
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  LEFT JOIN Badges bl ON bl.UserId = u.Id
WHERE
  u.CreationDate < CURRENT_TIMESTAMP
GROUP BY
  u.Id, u.DisplayName
HAVING
  COUNT(p.Id) > 0
ORDER BY
  AvgPostScore DESC, PostCount DESC
LIMIT 100;
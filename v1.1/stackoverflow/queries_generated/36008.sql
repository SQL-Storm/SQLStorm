-- {"query": "36008.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 309} 
SELECT
  u.Id AS UserId,
  u.DisplayName,
  COUNT(DISTINCT p.Id) AS PostCount,
  AVG(p.Score) AS AvgScore,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived,
  SUM(CASE WHEN v.VoteTypeId = 6 THEN 1 ELSE 0 END) AS CloseVotesCast,
  MIN(p.CreationDate) AS FirstPostDate,
  MAX(p.LastActivityDate) AS LastActivityDate,
  STRING_AGG(DISTINCT COALESCE(t.Name, ''), ',') AS TagsUsed
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN UNNEST(string_to_array(p.Tags, '>')) AS t ON true
  LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
WHERE
  u.Id IS NOT NULL
  AND p.Id IS NOT NULL
  AND p.PostTypeId IN (1, 2) -- Questions and Answers
GROUP BY
  u.Id, u.DisplayName
HAVING
  COUNT(DISTINCT p.Id) > 10
ORDER BY
  PostCount DESC, AvgScore DESC
LIMIT 100;
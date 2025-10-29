-- {"query": "5099.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 368} 
SELECT
  u.Id AS UserId,
  u.DisplayName AS UserName,
  u.Reputation,
  COUNT(*) AS PostCount,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
  AVG(p.Score) AS AvgPostScore,
  MAX(p.CreationDate) AS LastPostDate,
  COUNT(DISTINCT v.Id) AS VoteCount,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived,
  STRING_AGG(DISTINCT t.Name, ',') AS TagsInPosts,
  SUM(CASE WHEN p.OwnerUserId = u.Id THEN 1 ELSE 0 END) AS OwnPostsCount
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN UNNEST(string_to_array(p.Tags, '<>')) AS tname ON TRUE
  LEFT JOIN Tags t ON t.TagName = tname
WHERE
  u.CreationDate >= TIMESTAMP '2015-01-01 00:00:00'
  AND (u.LastAccessDate IS NOT NULL)
  AND (p.Id IS NULL OR p.Id IS NOT NULL)
GROUP BY
  u.Id, u.DisplayName, u.Reputation
HAVING
  COUNT(*) > 5
ORDER BY
  Reputation DESC, UserName
LIMIT 100;
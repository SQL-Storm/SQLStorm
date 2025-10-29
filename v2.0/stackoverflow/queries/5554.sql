-- {"query": "5554.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 328} 
SELECT
  u.Id AS UserId,
  u.DisplayName AS UserName,
  u.Reputation,
  COUNT(DISTINCT p.Id) AS QuestionCount,
  COUNT(DISTINCT a.Id) AS AnswerCount,
  AVG(p.Score) AS AvgQuestionScore,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived,
  STRING_AGG(DISTINCT t.TagName, ',') AS TopTags,
  MAX(p.LastActivityDate) AS LastActivity
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
  LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN PostLinks pl ON pl.PostId = p.Id
  LEFT JOIN Tags t ON t.Id = (SELECT t2.Id FROM Tags t2 WHERE t2.TagName = ANY(string_to_array(p.Tags, '>><<') ) LIMIT 1)
WHERE
  u.Reputation > 1000
  AND u.CreationDate < cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
GROUP BY
  u.Id, u.DisplayName, u.Reputation
HAVING
  COUNT(DISTINCT p.Id) > 0
ORDER BY
  LastActivity DESC
LIMIT 100;
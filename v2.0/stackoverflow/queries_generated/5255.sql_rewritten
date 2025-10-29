-- {"query": "5255.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 308} 
SELECT
  u.Id AS UserId,
  u.DisplayName AS UserName,
  u.Reputation,
  COUNT(DISTINCT p.Id) AS PostsCreated,
  AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
  AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AvgAnswerScore,
  COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpvotesReceived,
  COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownvotesReceived,
  MAX(p.LastActivityDate) AS LastActivity
FROM
  Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON v.PostId = p.Id
  AND v.CreationDate >= u.CreationDate - INTERVAL '1 year'
LEFT JOIN PostLinks pl ON pl.PostId = p.Id
LEFT JOIN Tags t ON t.Id = pl.RelatedPostId
WHERE
  u.AccountId IS NOT NULL
  AND u.Reputation > 100
  AND (p.PostTypeId = 1 OR p.PostTypeId = 2)
  AND (p.ClosedDate IS NULL OR p.ClosedDate > cast('2024-10-01 12:34:56' as timestamp))
GROUP BY
  u.Id, u.DisplayName, u.Reputation
ORDER BY
  PostsCreated DESC,
  LastActivity DESC
LIMIT 100;
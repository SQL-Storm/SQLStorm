-- {"query": "36093.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 303} 
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  COUNT(DISTINCT p.Id) AS PostsCreated,
  COUNT(DISTINCT v.PostId) FILTER (WHERE v.VoteTypeId = 2) AS UpvotesCast,
  COUNT(DISTINCT v.PostId) FILTER (WHERE v.VoteTypeId = 3) AS DownvotesCast,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived,
  MAX(p.CreationDate) AS LastPostDate,
  AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS NumQuestions,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS NumAnswers
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
GROUP BY
  u.Id, u.DisplayName, u.Reputation
HAVING
  COUNT(DISTINCT p.Id) > 0
ORDER BY
  PostsCreated DESC, u.Reputation DESC
LIMIT 100;
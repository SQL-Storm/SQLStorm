-- {"query": "6036.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 383} 
SELECT
  u.Id AS UserId,
  u.DisplayName AS UserName,
  u.Reputation,
  COUNT(DISTINCT p.Id) AS PostCount,
  AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
  AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AvgAnswerScore,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesGiven,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesGiven,
  MAX(p.LastActivityDate) AS LastActivity,
  STRING_AGG(CASE
               WHEN p.Title IS NOT NULL THEN p.Title
               ELSE NULL
             END, ' | ') FILTER (WHERE p.PostTypeId = 1) AS LastQuestionTitles,
  COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
  COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
  COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN p.Id END) AS AcceptedQuestions
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
WHERE
  u.AccountId IS NOT NULL
  AND u.Reputation > 1000
  AND (u.CreationDate < cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year')
GROUP BY
  u.Id, u.DisplayName, u.Reputation
HAVING
  COUNT(DISTINCT p.Id) > 5
ORDER BY
  Reputation DESC, LastActivity DESC
LIMIT 100;
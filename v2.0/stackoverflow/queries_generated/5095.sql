-- {"query": "5095.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 363} 
SELECT
  u.Id AS UserId,
  u.DisplayName AS UserName,
  u.Reputation,
  COUNT(DISTINCT p.Id) AS PostCount,
  AVG(p.Score) AS AvgPostScore,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
  MAX(p.LastActivityDate) AS LastActivePostDate,
  STRING_AGG(CASE WHEN b.Class = 1 THEN b.Name ELSE NULL END, ',') FILTER (WHERE b.Name IS NOT NULL) AS GoldBadges,
  COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadgeCount,
  SUM(CASE WHEN t.Name = 'Question' THEN 1 ELSE 0 END) AS QuestionCount,
  SUM(CASE WHEN t.Name = 'Answer' THEN 1 ELSE 0 END) AS AnswerCount
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN PostTypes t ON p.PostTypeId = t.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
WHERE
  u.AccountId IS NOT NULL
  AND u.Reputation > 100
  AND u.CreationDate < CURRENT_DATE - INTERVAL '1 year'
GROUP BY
  u.Id, u.DisplayName, u.Reputation
HAVING
  COUNT(DISTINCT p.Id) > 5
ORDER BY
  AvgPostScore DESC, PostCount DESC
LIMIT 100;
-- {"query": "82.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 354} 
SELECT
  u.Id AS UserId,
  u.DisplayName AS UserName,
  u.Reputation,
  COUNT(DISTINCT p.Id) AS PostCount,
  AVG(p.Score) AS AvgPostScore,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
  MAX(p.LastActivityDate) AS LastActive,
  STRING_AGG(CASE WHEN p.PostTypeId = 1 THEN p.Title ELSE NULL END, ' | ') AS LatestQuestionTitles,
  MAX(CASE WHEN p.PostTypeId = 1 THEN p.CreationDate END) AS MostRecentQuestionDate,
  COUNT(DISTINCT b.Id) AS BadgeCount,
  MIN(u.CreationDate) AS AccountCreatedDate
FROM
  Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON v.PostId = p.Id AND v.UserId = u.Id
LEFT JOIN Badges b ON b.UserId = u.Id
LEFT JOIN PostHistory ph ON ph.UserId = u.Id
WHERE
  u.AccountId IS NOT NULL
  AND (p.PostTypeId = 1 OR p.PostTypeId IS NULL)
  AND ph.PostId IS NULL OR ph.PostId IS NOT NULL -- include all history, but not filter out
GROUP BY
  u.Id, u.DisplayName, u.Reputation
HAVING
  COUNT(DISTINCT p.Id) > 0
ORDER BY
  Reputation DESC, UserName ASC
LIMIT 100;
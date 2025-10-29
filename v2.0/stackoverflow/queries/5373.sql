-- {"query": "5373.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 341} 
SELECT
  u.Id AS UserId,
  u.DisplayName AS UserName,
  u.Reputation,
  COALESCE(u.Location, 'Unknown') AS Location,
  COUNT(DISTINCT p.Id) AS PostCount,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven,
  AVG(CASE WHEN p.PostTypeId IN (1,2) THEN p.Score END) AS AvgPostScore,
  MAX(p.CreationDate) AS LastPostDate,
  STRING_AGG(CASE WHEN p.PostTypeId = 1 THEN p.Title ELSE NULL END, ' | ') AS LastQuestionTitles,
  CASE
    WHEN u.AccountId IS NULL THEN 'Guest'
    WHEN u.AccountId > 1000 THEN 'Member'
    ELSE 'User'
  END AS AccountTier
FROM
  Users u
LEFT JOIN Posts p
  ON p.OwnerUserId = u.Id
LEFT JOIN Votes v
  ON v.PostId = p.Id
  AND v.UserId = u.Id
LEFT JOIN PostHistory ph
  ON ph.PostId = p.Id
  AND ph.UserId = u.Id
WHERE
  u.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
  OR p.Id IS NULL
GROUP BY
  u.Id, u.DisplayName, u.Reputation, u.Location, u.AccountId
ORDER BY
  Reputation DESC, LastPostDate DESC
LIMIT 100;
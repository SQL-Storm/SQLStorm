-- {"query": "5845.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 407} 
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  COUNT(p.Id) AS PostCount,
  AVG(p.Score) AS AvgPostScore,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
  MAX(p.CreationDate) AS LastPostDate,
  COUNT(DISTINCT bh.Id) AS HistoryChanges,
  AVG(v.BountyAmount) FILTER (WHERE v.BountyAmount IS NOT NULL) AS AvgActiveBounty,
  STRING_AGG(CASE WHEN c.Score IS NULL THEN '' ELSE c.Text END, E'\n---\n') AS RecentComments,
  (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id) AS BadgeCount
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN PostHistory bh ON bh.UserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN Comments c ON c.PostId = p.Id
WHERE
  u.AccountId IS NOT NULL
  AND u.CreationDate >= (CURRENT_DATE - INTERVAL '2 years')
  AND (p.PostTypeId IS NULL OR p.PostTypeId IN (1, 2))
  AND (v.VoteTypeId IS NULL OR v.VoteTypeId IN (2, 3, 10, 11, 12, 14, 15, 16))
GROUP BY
  u.Id, u.DisplayName, u.Reputation
HAVING
  COUNT(p.Id) > 10 OR SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) > 0
ORDER BY
  Reputation DESC, LastPostDate DESC
LIMIT 100;
-- {"query": "64.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 411} 
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  COUNT(DISTINCT p.Id) AS PostCount,
  AVG(p.Score) AS AvgPostScore,
  SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) AS TotalQuestionViews,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
  MAX(p.LastActivityDate) AS LastActive,
  STRING_AGG(CASE WHEN v.VoteTypeId = 2 THEN 'up' WHEN v.VoteTypeId = 3 THEN 'down' END, ',' ORDER BY v.CreationDate) FILTER (WHERE v.PostId IS NOT NULL) AS VoteTypesSummary,
  COUNT(DISTINCT CASE WHEN b.Id IS NOT NULL THEN b.Id END) AS BadgeCount,
  SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
  SUM(CASE WHEN c.Score >= 0 THEN 1 ELSE 0 END) AS PositiveComments,
  MAX(CASE WHEN c.CreationDate IS NULL THEN NULL ELSE c.CreationDate END) AS LastCommentDate
FROM
  Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON v.PostId = p.Id
LEFT JOIN Badges b ON b.UserId = u.Id
LEFT JOIN Comments c ON c.PostId = p.Id
WHERE
  u.AccountId IS NOT NULL
  AND u.Reputation >= 1000
  AND (p.CreationDate IS NULL OR p.CreationDate > (CURRENT_DATE - INTERVAL '365 days'))
GROUP BY
  u.Id, u.DisplayName, u.Reputation
HAVING
  COUNT(DISTINCT p.Id) > 5
ORDER BY
  GoldBadges DESC,
  AvgPostScore DESC
LIMIT 100;
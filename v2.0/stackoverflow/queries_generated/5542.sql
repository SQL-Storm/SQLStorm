-- {"query": "5542.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 468} 
SELECT
  u.DisplayName AS UserName,
  u.Reputation,
  u.CreationDate AS UserSince,
  COUNT(p.Id) AS PostCount,
  AVG(p.Score) AS AvgPostScore,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
  STRING_AGG(DISTINCT tt.Name, ',') AS PostTypesTally,
  LAST_VALUE(p.LastActivityDate) OVER (PARTITION BY u.Id ORDER BY p.LastActivityDate ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS LastActivePostDate,
  COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
  COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
  MAX(p.ViewCount) AS MaxViewsOnPost,
  COALESCE(b.BadgeCount, 0) AS GoldBadges
FROM
  Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON v.PostId = p.Id AND v.UserId = u.Id
LEFT JOIN (
  SELECT OwnerUserId, COUNT(*) AS BadgeCount
  FROM Badges
  WHERE Class = 1
  GROUP BY OwnerUserId
) b ON b.OwnerUserId = u.Id
LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN PostHistory ph ON ph.PostId = p.Id
LEFT JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
LEFT JOIN (
  SELECT Id, Name FROM PostTypes
) tt ON p.PostTypeId = tt.Id
WHERE
  u.AccountId IS NOT NULL
  AND (p.CreationDate > NOW() - INTERVAL '3 years' OR p.CreationDate IS NULL)
GROUP BY
  u.Id, u.DisplayName, u.Reputation, u.CreationDate, b.BadgeCount
ORDER BY
  AVG(p.Score) DESC
LIMIT 100;
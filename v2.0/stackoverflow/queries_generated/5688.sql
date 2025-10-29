-- {"query": "5688.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 423} 
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  COUNT(DISTINCT p.Id) AS PostCount,
  AVG(p.Score) AS AvgPostScore,
  SUM(p.ViewCount) AS TotalViews,
  MAX(p.CreationDate) AS LastPostDate,
  STRING_AGG(DISTINCT tt.Name, ',') AS PostTypesHeld,
  COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpVotesCast,
  COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownVotesCast,
  SUM(CASE WHEN v.VoteTypeId = 6 THEN 1 ELSE 0 END) AS CloseVotesCast,
  COUNT(DISTINCT CASE WHEN b.Id IS NOT NULL THEN b.Id END) AS BadgesEarned
FROM
  Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON v.PostId = p.Id
LEFT JOIN Badges b ON b.UserId = u.Id
LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN (
  SELECT DISTINCT p.OwnerUserId, b.Id
  FROM Badges b
  WHERE b.Class IN (1,2,3)
) AS b ON b.OwnerUserId = u.Id
LEFT JOIN PostHistory ph ON ph.PostId = p.Id
LEFT JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
LEFT JOIN (
  SELECT Id, Name FROM PostHistoryTypes WHERE Name IN ('Created', 'Initial Title')
) AS tt ON 1=1
WHERE
  u.Id IS NOT NULL
  AND (p.Id IS NULL OR p.Id > 0)
GROUP BY
  u.Id,
  u.DisplayName,
  u.Reputation
HAVING
  COUNT(DISTINCT p.Id) > 0
ORDER BY
  TotalViews DESC,
  AvgPostScore DESC
LIMIT 100;
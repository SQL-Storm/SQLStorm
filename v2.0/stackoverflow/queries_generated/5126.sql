-- {"query": "5126.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 393} 
SELECT
  u.DisplayName AS TopUser,
  u.Id AS UserId,
  u.Reputation,
  COUNT(p.Id) AS PostCount,
  AVG(p.Score) AS AvgPostScore,
  MAX(p.LastActivityDate) AS LastActivePostDate,
  STRING_AGG(DISTINCT t.Name, ';') AS PostTypesPresent,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven,
  COUNT(DISTINCT cl.Id) AS ClosedPostsCount,
  MIN(p.CreationDate) AS FirstPostDate,
  MAX(p.CreationDate) AS MostRecentPostDate,
  COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) OVER (), 0) AS TotalQuestions,
  COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) OVER (), 0) AS TotalAnswers
FROM
  Users u
LEFT JOIN Posts p
  ON p.OwnerUserId = u.Id
LEFT JOIN PostTypes t
  ON p.PostTypeId = t.Id
LEFT JOIN Votes v
  ON v.PostId = p.Id
LEFT JOIN Comments cl
  ON cl.PostId = p.Id
WINDOW w AS (
  PARTITION BY u.Id
  ORDER BY p.CreationDate
)
WHERE
  u.Reputation > 1000
  AND u.CreationDate < NOW() - INTERVAL '180 days'
GROUP BY
  u.Id, u.DisplayName, u.Reputation
HAVING
  COUNT(p.Id) > 0
ORDER BY
  AvgPostScore DESC, PostCount DESC
LIMIT 100;
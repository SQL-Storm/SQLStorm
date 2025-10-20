-- {"query": "36094.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 287} 
SELECT
  u.Id AS UserId,
  u.DisplayName,
  COUNT(DISTINCT p.Id) AS PostsCount,
  SUM(COALESCE(p.ViewCount, 0)) AS TotalViews,
  AVG(COALESCE(p.Score, 0)) AS AvgPostScore,
  MAX(p.CreationDate) AS LastPostDate,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived,
  COUNT(DISTINCT CASE WHEN b.Id IS NOT NULL THEN b.Id END) AS BadgesEarned
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
WHERE
  u.CreationDate >= NOW() - INTERVAL '5 years'
  AND (p.Id IS NULL OR p.PostTypeId IN (1, 2)) -- focus on questions/answers
GROUP BY
  u.Id, u.DisplayName
HAVING
  COUNT(DISTINCT p.Id) > 0
ORDER BY
  TotalViews DESC, PostsCount DESC
LIMIT 100;
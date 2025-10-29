-- {"query": "5120.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 399} 
SELECT
  u.DisplayName AS UserName,
  u.Location AS UserLocation,
  u.Reputation,
  COUNT(DISTINCT p.Id) AS PostCount,
  SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
  SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
  AVG(p.Score) AS AvgPostScore,
  SUM(p.ViewCount) AS TotalViews,
  MAX(p.CreationDate) AS LastActivePostDate,
  ARRAY_AGG(DISTINCT t.Name) FILTER (WHERE t.Name IS NOT NULL) AS TagsUsed,
  COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS Upvotes,
  COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS Downvotes,
  SUM(CASE WHEN b.Id IS NOT NULL THEN 1 ELSE 0 END) AS HasBadges
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN PostLinks pl ON pl.PostId = p.Id
  LEFT JOIN (SELECT Id, Name FROM PostTypes) AS t ON t.Id = p.PostTypeId
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
WHERE
  u.Id IS NOT NULL
  AND p.CreationDate >= DATE_TRUNC('year', cast('2024-10-01' as date)) -- posts created this year
GROUP BY
  u.Id, u.DisplayName, u.Location, u.Reputation
HAVING
  COUNT(DISTINCT p.Id) > 10
ORDER BY
  TotalViews DESC, LastActivePostDate DESC
LIMIT 100;
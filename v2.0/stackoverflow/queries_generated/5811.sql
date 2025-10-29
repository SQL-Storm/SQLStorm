-- {"query": "5811.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 439} 
SELECT
  u.Id AS UserId,
  u.DisplayName,
  COUNT(DISTINCT p.Id) AS PostCount,
  AVG(p.Score) AS AvgPostScore,
  SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) AS TotalQuestionViews,
  SUM(CASE WHEN p.PostTypeId = 2 THEN p.ViewCount ELSE 0 END) AS TotalAnswerViews,
  MAX(p.LastActivityDate) AS LastActivity,
  STRING_AGG(DISTINCT tt.Name, ',') FILTER (WHERE p.PostTypeId = 1) AS TopTags,
  COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpvotesReceived,
  COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownvotesReceived,
  COUNT(DISTINCT CASE WHEN v.VoteTypeId = 16 THEN v.Id END) AS ModeratorReviews,
  COUNT(DISTINCT CASE WHEN b.Id IS NOT NULL THEN b.Id END) AS BadgesEarned
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id AND v.UserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  LEFT JOIN UNNEST(string_to_array(p.Tags, '<>')) AS t(tag) -- placeholder for tag extraction; replaced by valid syntax per DB
  LEFT JOIN (SELECT Id, Name FROM PostTypes) AS pt ON pt.Id = p.PostTypeId
  LEFT JOIN (SELECT Id, Name FROM PostHistoryTypes) AS h ON h.Id = p.Id
  LEFT JOIN (SELECT Id, Name FROM Tags) AS tt ON tt.Id = p.Id
WHERE
  u.AccountId IS NOT NULL
  AND u.Reputation > 0
GROUP BY
  u.Id, u.DisplayName
HAVING
  COUNT(p.Id) > 0
ORDER BY
  AvgPostScore DESC, PostCount DESC
LIMIT 100;
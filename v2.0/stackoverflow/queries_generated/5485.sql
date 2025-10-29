-- {"query": "5485.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 429} 
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  COUNT(DISTINCT p.Id) AS PostsCount,
  AVG(p.Score) AS AvgPostScore,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived,
  SUM(CASE WHEN b.Id IS NOT NULL THEN 1 ELSE 0 END) AS BadgesCount,
  SUM(CASE WHEN c.Id IS NOT NULL THEN 1 ELSE 0 END) AS CommentsCount,
  MIN(p.CreationDate) AS FirstPostDate,
  MAX(p.LastActivityDate) AS LastActivityDate,
  STRING_AGG(DISTINCT t.Name, ',') AS TagsTouched,
  AVG(NULLIF(DATEDIFF(day, u.CreationDate::date, NOW()::date), 0)) AS AgeInDays
FROM
  Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id AND v.UserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  LEFT JOIN Comments c ON c.PostId = p.Id
  LEFT JOIN (
    SELECT
      ph.PostId,
      ph.Text,
      ph.CreationDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (1, 4, 5, 6, 10, 11, 16) -- representative history types
  ) h ON h.PostId = p.Id
  LEFT JOIN (SELECT Id, Name FROM Tags) t ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
GROUP BY
  u.Id, u.DisplayName, u.Reputation
HAVING
  COUNT(DISTINCT p.Id) > 0
ORDER BY
  Reputation DESC, PostsCount DESC
LIMIT 100;
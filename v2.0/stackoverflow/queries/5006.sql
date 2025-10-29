-- {"query": "5006.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 691}
WITH
RecentPopularQuestions AS (
  SELECT
    p.Id AS QuestionId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.CommentCount,
    p.Tags,
    p.OwnerUserId,
    p.OwnerDisplayName,
    ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC, p.Score DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.ClosedDate IS NULL
),
TagAggregation AS (
  SELECT
    tag AS TagName,
    COUNT(*) AS QuestionCount,
    AVG(p.ViewCount) AS AvgViews,
    AVG(p.Score) AS AvgScore
  FROM Posts p
  JOIN RecentPopularQuestions r ON p.Id = r.QuestionId
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substring(p.Tags FROM 2 FOR char_length(p.Tags) - 2), '><')) AS tag
  ) t
  GROUP BY tag
),
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalQuestions,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
    SUM(CASE WHEN c.Id IS NOT NULL THEN 1 ELSE 0 END) AS CommentCount
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN Comments c ON c.PostId = p.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
Correlation AS (
  SELECT
    r.QuestionId,
    r.Title,
    r.ViewCount,
    r.Score,
    r.CommentCount,
    r.Tags,
    u.Id AS UserId,
    u.DisplayName AS OwnerName,
    u.Reputation,
    ROW_NUMBER() OVER (PARTITION BY r.QuestionId ORDER BY v.CreationDate DESC NULLS LAST) AS rev
  FROM RecentPopularQuestions r
  LEFT JOIN Posts p ON p.Id = r.QuestionId
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN Users u ON u.Id = p.OwnerUserId
)
SELECT
  q.Id AS QuestionId,
  q.Title,
  q.CreationDate,
  q.ViewCount,
  q.Score,
  q.CommentCount,
  q.Tags,
  ta.AvgViews AS AverageTagViews,
  ta.AvgScore AS AverageTagScore,
  t.TagName,
  ua.UserId AS AuthorUserId,
  ua.DisplayName AS AuthorName,
  ua.Reputation AS AuthorReputation
FROM Correlation ca
CROSS JOIN LATERAL (
  SELECT unnest(string_to_array(substring(ca.Tags FROM 2 FOR char_length(ca.Tags) - 2), '><')) AS TagName
) t
JOIN TagAggregation ta ON ta.TagName = t.TagName
JOIN UserActivity ua ON ua.UserId = ca.UserId
JOIN Posts q ON q.Id = ca.QuestionId
LEFT JOIN LATERAL (
  SELECT COUNT(*) AS dummy
) d ON true
WHERE ca.rev = 1
ORDER BY q.ViewCount DESC, q.Score DESC
LIMIT 100;
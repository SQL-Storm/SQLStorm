-- {"query": "5483.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 566} 
WITH TopQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.Tags,
    p.OwnerUserId,
    p.LastActivityDate,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ContentLicense,
    u.DisplayName AS OwnerName,
    u.Reputation,
    ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1 -- Question
    AND p.ClosedDate IS NULL
),
RecentActivity AS (
  SELECT
    t.PostId,
    t.LastActivityDate,
    t.Tags,
    t.OwnerName,
    t.Reputation,
    t.rn,
    LAG(t.LastActivityDate) OVER (PARTITION BY t.OwnerName ORDER BY t.LastActivityDate) AS PrevActivity
  FROM TopQuestions t
),
TagStats AS (
  SELECT
    unnest(string_to_array(substr(t.Tags, 2, length(t.Tags)-2), '> <')) AS tag,
    COUNT(*) AS PostCount,
    AVG(p.Score) AS AvgScore,
    MAX(p.ViewCount) AS MaxViews
  FROM RecentActivity ra
  JOIN Posts p ON p.Id = ra.PostId
  GROUP BY unnest(string_to_array(substr(t.Tags, 2, length(t.Tags)-2), '> <'))
)
SELECT
  q.PostId,
  q.Title,
  q.CreationDate,
  q.ViewCount,
  q.Score,
  q.Tags,
  q.OwnerName,
  q.Reputation,
  q.LastActivityDate,
  q.AnswerCount,
  q.CommentCount,
  q.FavoriteCount,
  q.ContentLicense,
  -- Windowed rank within each dynamic tag group (derived from Tags)
  ROW_NUMBER() OVER (PARTITION BY qa.Tag ORDER BY q.Score DESC, q.ViewCount DESC, q.CreationDate DESC) AS TagRank
FROM RecentActivity ra
JOIN TopQuestions q ON ra.PostId = q.PostId
LEFT JOIN LATERAL (
  SELECT unnest(string_to_array(substr(q.Tags, 2, length(q.Tags)-2), '> <')) AS Tag
) AS qa ON true
LEFT JOIN Badges b ON b.UserId = q.OwnerUserId
LEFT JOIN PostLinks pl ON pl.PostId = q.PostId
LEFT JOIN Votes v ON v.PostId = q.PostId
WHERE qa.Tag IS NOT NULL
ORDER BY q.LastActivityDate DESC
LIMIT 200;
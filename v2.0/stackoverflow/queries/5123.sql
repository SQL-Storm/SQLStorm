-- {"query": "5123.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 888}
WITH recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount
  FROM Posts p
  WHERE p.PostTypeId = 1
),
tag_summary AS (
  SELECT
    unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName,
    p.Id AS PostId
  FROM Posts p
  WHERE p.PostTypeId = 1
),
tag_popularity AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagCount,
    SUM(p.ViewCount) AS TotalViews,
    AVG(p.Score) AS AvgScore
  FROM tag_summary t
  JOIN Posts p ON p.Id = t.PostId
  GROUP BY t.TagName
),
author_activity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    COUNT(DISTINCT r.PostId) AS PostsCreated,
    MAX(p.LastActivityDate) AS LastActive
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN PostLinks r ON r.PostId = p.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
top_posts AS (
  SELECT
    r.PostId,
    r.Title,
    r.Tags,
    r.CreationDate,
    r.Score,
    r.ViewCount,
    r.OwnerUserId,
    r.CommentCount,
    r.AnswerCount,
    r.FavoriteCount,
    ROW_NUMBER() OVER (
      PARTITION BY r.OwnerUserId
      ORDER BY r.Score DESC, r.ViewCount DESC, r.CreationDate DESC
    ) AS rn
  FROM recent_questions r
),
filtered_top AS (
  SELECT *
  FROM top_posts
  WHERE rn = 1
),
complex_metrics AS (
  SELECT
    f.Title AS QuestionTitle,
    f.PostId,
    f.OwnerUserId,
    f.Score,
    f.ViewCount,
    f.CommentCount,
    f.AnswerCount,
    f.FavoriteCount,
    u.DisplayName AS OwnerDisplayName,
    a.Reputation AS OwnerReputation,
    CASE
      WHEN f.ViewCount > 1000 THEN 'HighTraffic'
      WHEN f.ViewCount > 100 AND f.ViewCount <= 1000 THEN 'MediumTraffic'
      ELSE 'LowTraffic'
    END AS TrafficBand,
    ARRAY_AGG(DISTINCT ts_sum.TagName) AS TagsInQuestion,
    ts_sum.TagName AS TagName,
    tp.TagCount,
    tp.TotalViews,
    tp.AvgScore
  FROM filtered_top f
  LEFT JOIN Users u ON u.Id = f.OwnerUserId
  LEFT JOIN author_activity a ON a.UserId = u.Id
  LEFT JOIN tag_summary ts_sum ON ts_sum.PostId = f.PostId
  LEFT JOIN tag_popularity tp ON tp.TagName = ts_sum.TagName
  GROUP BY
    f.Title,
    f.PostId,
    f.OwnerUserId,
    f.Score,
    f.ViewCount,
    f.CommentCount,
    f.AnswerCount,
    f.FavoriteCount,
    u.DisplayName,
    a.Reputation,
    ts_sum.TagName,
    tp.TagCount,
    tp.TotalViews,
    tp.AvgScore
)
SELECT
  c.QuestionTitle,
  c.PostId,
  c.OwnerDisplayName,
  c.OwnerReputation,
  c.Score,
  c.ViewCount,
  c.CommentCount,
  c.AnswerCount,
  c.FavoriteCount,
  c.TrafficBand,
  c.TagsInQuestion,
  c.TagName,
  c.TagCount,
  c.TotalViews,
  c.AvgScore,
  (c.TotalViews / NULLIF(c.TagCount, 0)) AS ViewsPerTagRatio
FROM complex_metrics c
ORDER BY c.OwnerReputation DESC NULLS LAST, c.ViewCount DESC, c.Score DESC
LIMIT 100;
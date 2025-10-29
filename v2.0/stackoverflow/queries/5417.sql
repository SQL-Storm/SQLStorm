-- {"query": "5417.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 777}
WITH RecentActivePosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.ContentLicense,
    u.Reputation,
    u.DisplayName AS OwnerDisplayName,
    u.Location,
    u.AccountId,
    ROW_NUMBER() OVER (
      PARTITION BY CAST(p.LastActivityDate AS date)
      ORDER BY p.LastActivityDate DESC, p.Score DESC
    ) AS rn_day
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId IN (1, 2)
    AND p.LastActivityDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
),
TaggedActivity AS (
  SELECT
    r.PostId,
    r.PostTypeId,
    r.Title,
    t.TagName,
    r.LastActivityDate,
    r.Reputation,
    r.OwnerDisplayName,
    r.rn_day,
    r.Score,
    r.ViewCount,
    r.CommentCount,
    r.AnswerCount,
    r.FavoriteCount,
    r.Tags,
    r.OwnerUserId
  FROM RecentActivePosts r
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(
      substring(r.Tags, 2, length(r.Tags)-2), '><'
    )) AS TagName
  ) t
),
AggregatedTags AS (
  SELECT
    TagName,
    COUNT(*) AS PostsWithTag,
    AVG(Score) AS AvgPostScore,
    SUM(ViewCount) AS TotalViews,
    MAX(LastActivityDate) AS LastActive
  FROM TaggedActivity
  GROUP BY TagName
),
TopTags AS (
  SELECT
    a.TagName,
    a.PostsWithTag,
    a.AvgPostScore,
    a.TotalViews,
    a.LastActive
  FROM AggregatedTags a
  ORDER BY a.TotalViews DESC, a.AvgPostScore DESC
  LIMIT 50
),
CrossJoined AS (
  SELECT
    t.TagName,
    t.LastActive,
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.OwnerUserId,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    u.Reputation AS OwnerReputation,
    u.DisplayName AS OwnerDisplayName,
    p.LastActivityDate
  FROM TopTags t
  JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.LastActivityDate = t.LastActive
     OR p.LastActivityDate = (
       SELECT MAX(LastActivityDate) FROM Posts WHERE Tags LIKE '%' || t.TagName || '%'
     )
)
SELECT
  c.TagName,
  c.PostId,
  c.Title,
  c.OwnerDisplayName,
  c.OwnerReputation,
  c.ViewCount,
  c.Score,
  c.CreationDate,
  c.LastActive,
  c.OwnerUserId,
  c.Tags,
  c.AnswerCount,
  c.CommentCount,
  c.FavoriteCount,
  (COALESCE(c.Score, 0) * 2.0 + COALESCE(c.ViewCount, 0) / NULLIF(COALESCE(t2.PG_TABLE_SIZE, 0) + 1, 0)) AS PerformanceMetric
FROM CrossJoined c
LEFT JOIN (
  SELECT 1 AS PG_TABLE_SIZE
) AS t2 ON TRUE
ORDER BY c.LastActive DESC, c.ViewCount DESC
LIMIT 100;
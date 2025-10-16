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
    p.FavoriteCount
  FROM Posts p
  WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30 days'
),
TagHotness AS (
  SELECT
    t.TagName,
    AVG(rap.Score) AS avg_score,
    SUM(rap.ViewCount) AS total_views,
    COUNT(DISTINCT rap.OwnerUserId) AS unique_contributors,
    MAX(rap.LastActivityDate) AS last_activity
  FROM RecentActivePosts rap
  JOIN LATERAL (
    SELECT unnest(string_to_array(substring(rap.Tags, 2, length(rap.Tags) - 2), '><')) AS TagName
  ) t ON TRUE
  GROUP BY t.TagName
),
TopTags AS (
  SELECT
    t.TagName,
    t.avg_score,
    t.total_views,
    t.unique_contributors,
    t.last_activity
  FROM TagHotness t
  ORDER BY t.total_views DESC, t.avg_score DESC
  LIMIT 20
),
CorrelatedSubquery AS (
  SELECT
    rp.PostId,
    rp.Title AS PostTitle,
    rp.Tags,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.Score,
    rp.ViewCount,
    ua.DisplayName AS OwnerDisplayName,
    ARRAY_AGG(DISTINCT v.VoteTypeId) FILTER (WHERE v.UserId IS NOT NULL) AS voter_types,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.PostId) AS CommentCount
  FROM RecentActivePosts rp
  LEFT JOIN Users ua ON rp.OwnerUserId = ua.Id
  LEFT JOIN Votes v ON v.PostId = rp.PostId
  GROUP BY rp.PostId, rp.Title, rp.Tags, rp.CreationDate, rp.LastActivityDate, rp.Score, rp.ViewCount, ua.DisplayName
),
WindowedStats AS (
  SELECT
    ct.TagName,
    ct.total_views,
    ct.avg_score,
    ROW_NUMBER() OVER (ORDER BY ct.total_views DESC, ct.avg_score DESC) AS rn
  FROM TopTags ct
)
SELECT
  wp.PostId,
  wp.PostTitle,
  wp.Tags,
  wp.CreationDate,
  wp.LastActivityDate,
  wp.Score,
  wp.ViewCount,
  wp.OwnerDisplayName,
  wp.CommentCount,
  ws.rn AS rank_by_views
FROM CorrelatedSubquery wp
JOIN TopTags tt ON tt.TagName IN (
  SELECT regexp_split_to_table(substring(wp.Tags, 2, length(wp.Tags) - 2), '><')
)
JOIN WindowedStats ws ON ws.TagName = tt.TagName
ORDER BY ws.rn
LIMIT 100;
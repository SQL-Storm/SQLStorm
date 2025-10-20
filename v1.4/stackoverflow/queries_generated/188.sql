-- {"query": "188.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 1795} 
WITH
user_posts AS (
  SELECT
    u.Id AS UserId,
    p.Id AS PostId,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.Title,
    p.Tags
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
),
user_ranked AS (
  SELECT
    up.UserId,
    up.PostId,
    up.Score,
    up.ViewCount,
    up.CreationDate,
    up.LastActivityDate,
    ROW_NUMBER() OVER (PARTITION BY up.UserId ORDER BY up.Score DESC NULLS LAST, up.ViewCount DESC NULLS LAST) AS rn
  FROM user_posts up
),
user_metrics AS (
  SELECT
    u.Id AS UserId,
    COUNT(p.Id) AS TotalPosts,
    SUM(p.ViewCount) AS TotalViews,
    AVG(CASE WHEN p.Score IS NULL THEN 0 ELSE p.Score END) AS AvgScore,
    SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) AS UpvotedPosts,
    MAX(p.LastActivityDate) AS LastPostActivity
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id
),
badge_counts AS (
  SELECT
    b.UserId,
    COUNT(*) AS BadgeCount
  FROM Badges b
  GROUP BY b.UserId
),
recent_posts AS (
  SELECT
    up.UserId,
    MAX(up.LastActivityDate) AS LastActivityDate
  FROM user_posts up
  GROUP BY up.UserId
),
common AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COALESCE(m.TotalPosts, 0) AS TotalPosts,
    COALESCE(m.TotalViews, 0) AS TotalViews,
    COALESCE(m.AvgScore, 0) AS AvgScore,
    COALESCE(b.BadgeCount, 0) AS BadgeCount,
    COALESCE(rp.LastPostActivity, u.CreationDate) AS LastActivityDate,
    ROW_NUMBER() OVER (ORDER BY COALESCE(m.TotalViews, 0) DESC, u.Reputation DESC, COALESCE(m.TotalPosts, 0) DESC) AS OverallRank
  FROM Users u
  LEFT JOIN user_metrics m ON m.UserId = u.Id
  LEFT JOIN badge_counts b ON b.UserId = u.Id
  LEFT JOIN recent_posts rp ON rp.UserId = u.Id
),
latest_activity AS (
  SELECT
    c.UserId,
    MAX(c.LastActivityDate) AS LastActivityDate,
    STRING_AGG(DISTINCT t.TagName, ',') AS TagsUsed
  FROM common c
  LEFT JOIN Posts p ON p.OwnerUserId = c.UserId
  LEFT JOIN LATERAL (SELECT unnest(string_to_array(p.Tags, '>><<')) AS TagName) t ON TRUE
  GROUP BY c.UserId
)
SELECT
  la.UserId,
  u.DisplayName,
  c.TotalPosts,
  c.TotalViews,
  c.AvgScore,
  c.BadgeCount,
  la.LastActivityDate,
  la.TagsUsed,
  c.OverallRank
FROM common c
LEFT JOIN Users u ON u.Id = c.UserId
LEFT JOIN latest_activity la ON la.UserId = c.UserId
UNION ALL
SELECT
  u.Id AS UserId,
  u.DisplayName,
  CAST(NULL AS INTEGER) AS TotalPosts,
  CAST(NULL AS BIGINT) AS TotalViews,
  CAST(NULL AS NUMERIC(10,2)) AS AvgScore,
  CAST(NULL AS INTEGER) AS BadgeCount,
  NULL AS LastActivityDate,
  NULL AS TagsUsed,
  CAST(NULL AS INTEGER) AS OverallRank
FROM Users u
ORDER BY OverallRank NULLS LAST, LastActivityDate DESC NULLS LAST
LIMIT 100;
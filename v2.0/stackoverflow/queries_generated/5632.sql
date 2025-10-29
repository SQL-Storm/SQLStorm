-- {"query": "5632.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 667} 
WITH hot_posts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.PostTypeId,
    p.AcceptedAnswerId,
    p.LastActivityDate,
    p.CommentCount,
    p.FavoriteCount
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
),
recent_activity AS (
  SELECT
    hp.PostId,
    hp.Title,
    hp.Tags,
    hp.CreationDate,
    hp.Score,
    hp.ViewCount,
    u.DisplayName AS OwnerName,
    u.Reputation,
    p2.LastActivityDate,
    -- window function: rank recent activity per day
    ROW_NUMBER() OVER (PARTITION BY DATE(hp.CreationDate) ORDER BY hp.Score DESC, hp.ViewCount DESC) AS rn_per_day
  FROM hot_posts hp
  LEFT JOIN Users u ON hp.OwnerUserId = u.Id
  LEFT JOIN Posts p2 ON hp.Id = p2.ParentId OR hp.Id = p2.Id
),
tag_popularity AS (
  SELECT
    unnest(string_to_array(substr(hp.Tags, 2, length(hp.Tags)-2), '><')) AS TagName,
    COUNT(*) AS TagScore
  FROM recent_activity hp
  GROUP BY 1
),
top_tags AS (
  SELECT
    TagName,
    TagScore,
    ROW_NUMBER() OVER (ORDER BY TagScore DESC, TagName) AS tag_rank
  FROM tag_popularity
  WHERE TagName IS NOT NULL
  FETCH FIRST 10 ROWS ONLY
),
complex_filters AS (
  SELECT
    ra.PostId,
    ra.Title,
    ra.Tags,
    ra.CreationDate,
    ra.Score,
    ra.ViewCount,
    ra.OwnerName,
    ra.Reputation,
    ra.LastActivityDate,
    ra.rn_per_day,
    tt.TagName
  FROM recent_activity ra
  LEFT JOIN top_tags tt ON TRUE
  WHERE ra.rn_per_day <= 3
    OR ra.Score > 5
    OR ra.ViewCount > 1000
),
cross_checks AS (
  SELECT
    cf.PostId,
    cf.Title,
    cf.Tags,
    cf.CreationDate,
    cf.Score,
    cf.ViewCount,
    cf.OwnerName,
    cf.Reputation,
    cf.LastActivityDate,
    cf.TagName,
    CASE
      WHEN cf.TagName IS NOT NULL THEN true
      ELSE false
    END AS HasTagBoost
  FROM complex_filters cf
  LEFT JOIN LATERAL (
    SELECT 1
  ) AS l ON true
  ORDER BY cf.LastActivityDate DESC
  LIMIT 100
)
SELECT
  cc.PostId,
  cc.Title,
  cc.Tags,
  cc.CreationDate,
  cc.Score,
  cc.ViewCount,
  cc.OwnerName,
  cc.Reputation,
  cc.LastActivityDate,
  cc.TagName,
  cc.HasTagBoost
FROM cross_checks cc
ORDER BY cc.LastActivityDate DESC, cc.Score DESC, cc.ViewCount DESC;
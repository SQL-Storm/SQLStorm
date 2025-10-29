-- {"query": "5124.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 593}
WITH recent_post_activity AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.ViewCount,
    p.Score,
    p.CommentCount,
    COALESCE(p.AnswerCount, 0) AS AnswerCount,
    p.FavoriteCount,
    p.ContentLicense,
    u.Reputation,
    u.DisplayName AS OwnerDisplayName,
    u.Location,
    u.AccountId,
    ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY ph.CreationDate DESC) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId = 16
  WHERE p.PostTypeId IN (1,2)
),
tag_influence AS (
  SELECT
    rp.PostId,
    rp.Title,
    tag AS TagName,
    COUNT(*) OVER (PARTITION BY rp.PostId) AS tag_count
  FROM recent_post_activity rp,
  LATERAL (
    SELECT unnest(string_to_array(substring(rp.Tags, 2, length(rp.Tags)-2), '><')) AS tag
  ) t
),
corr AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.OwnerDisplayName,
    rp.Reputation,
    rp.ViewCount,
    rp.Score,
    rp.CommentCount,
    rp.AnswerCount,
    rp.FavoriteCount,
    rp.ContentLicense,
    ti.TagName,
    ti.tag_count,
    DENSE_RANK() OVER (ORDER BY rp.ViewCount DESC, rp.Score DESC) AS view_score
  FROM recent_post_activity rp
  LEFT JOIN tag_influence ti ON ti.PostId = rp.PostId
)
SELECT
  c.PostId,
  c.Title,
  c.OwnerDisplayName,
  c.Reputation,
  c.ViewCount,
  c.Score,
  c.CommentCount,
  c.AnswerCount,
  c.FavoriteCount,
  c.ContentLicense,
  c.TagName,
  c.tag_count,
  c.view_score,
  COUNT(*) OVER (PARTITION BY c.OwnerDisplayName) AS posts_by_owner,
  AVG(c.Score) OVER (PARTITION BY c.OwnerDisplayName) AS avg_score_by_owner,
  SUM(c.ViewCount) OVER (PARTITION BY c.TagName) AS total_views_for_tag
FROM corr c
WHERE
  c.view_score <= 1000
  AND c.TagName IS NOT NULL
ORDER BY c.view_score DESC, c.Reputation DESC
LIMIT 100;
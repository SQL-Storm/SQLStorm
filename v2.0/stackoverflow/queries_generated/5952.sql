-- {"query": "5952.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 811} 
WITH ranked_posts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.OwnerDisplayName,
    p.PostTypeId,
    p.ParentId,
    p.AcceptedAnswerId,
    p.CommentCount,
    p.FavoriteCount,
    p.ContentLicense,
    u.Reputation,
    u.DisplayName AS OwnerDisplayNameSQL,
    u.UpVotes,
    u.DownVotes,
    w.Name AS PostTypeName
  FROM Posts p
  LEFT JOIN PostTypes w ON p.PostTypeId = w.Id
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
),
cte_recent_activity AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.Tags,
    rp.Score,
    rp.ViewCount,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.OwnerUserId,
    rp.OwnerDisplayName,
    rp.PostTypeId,
    rp.ParentId,
    rp.AcceptedAnswerId,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.ContentLicense,
    rp.Reputation
  FROM ranked_posts rp
  WHERE rp.LastActivityDate >= NOW() - INTERVAL '30 days'
),
corr AS (
  SELECT
    c.PostId,
    c.Title,
    c.Tags,
    c.Score,
    c.ViewCount,
    c.CreationDate,
    c.LastActivityDate,
    c.OwnerUserId,
    c.OwnerDisplayName,
    c.PostTypeId,
    c.ParentId,
    c.AcceptedAnswerId,
    c.CommentCount,
    c.FavoriteCount,
    c.ContentLicense,
    c.Reputation,
    ROW_NUMBER() OVER (ORDER BY c.LastActivityDate DESC, c.Score DESC) AS rn
  FROM cte_recent_activity c
),
window_stats AS (
  SELECT
    PostId,
    Title,
    Tags,
    Score,
    ViewCount,
    CreationDate,
    LastActivityDate,
    OwnerUserId,
    OwnerDisplayName,
    PostTypeId,
    ParentId,
    AcceptedAnswerId,
    CommentCount,
    FavoriteCount,
    ContentLicense,
    Reputation,
    rn,
    SUM(1) OVER (PARTITION BY PostTypeId ORDER BY LastActivityDate DESC ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING) AS neighbor_count
  FROM corr
),
enhanced AS (
  SELECT
    w.*,
    CASE
      WHEN PostTypeId = 1 THEN 'Question'
      WHEN PostTypeId = 2 THEN 'Answer'
      ELSE 'Other'
    END AS TypeLabel,
    -- example complex expression: a derived score combining score, views, reputation, and a null-safe count
    (Score * 2 + ViewCount / NULLIF(Reputation,0)::float) AS composite_score,
    -- string expression: a normalized tag phrase
    LOWER(REGEXP_REPLACE(Tags, '[<>]', '', 'g')) AS normalized_tags
  FROM window_stats w
)
SELECT
  PostId,
  Title,
  Tags,
  ViewCount,
  Score,
  LastActivityDate,
  CreationDate,
  OwnerUserId,
  OwnerDisplayName,
  TypeLabel,
  composite_score,
  neighbor_count,
  Reputation,
  normalized_tags
FROM enhanced
LEFT JOIN Badges b
  ON b.UserId = enhanced.OwnerUserId
WHERE
  (PostTypeId = 1 AND CommentCount > 5)
  OR (PostTypeId = 2 AND Score > 0)
  OR (normalized_tags LIKE '%sql%' OR normalized_tags LIKE '%performance%')
ORDER BY composite_score DESC, LastActivityDate DESC
LIMIT 100;
-- {"query": "5679.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 890} 
WITH TopPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.OwnerDisplayName,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.PostTypeId,
    p.ContentLicense,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY p.Score DESC, p.ViewCount DESC, p.LastActivityDate DESC
    ) AS rn_by_type
  FROM Posts p
  WHERE p.PostTypeId = 1 -- questions
    AND p.CreationDate >= NOW() - INTERVAL '365 days'
),
TagFrequency AS (
  SELECT
    unnest(string_to_array(p.Tags, '><')) AS tag,
    COUNT(*) AS tag_count
  FROM TopPosts p
  GROUP BY 1
),
TagRank AS (
  SELECT
    tag,
    tag_count,
    ROW_NUMBER() OVER (ORDER BY tag_count DESC, tag) AS tag_rank
  FROM TagFrequency
  WHERE tag IS NOT NULL
),
Enriched AS (
  SELECT
    tp.PostId,
    tp.Title,
    tp.Tags,
    tp.CreationDate,
    tp.Score,
    tp.ViewCount,
    tp.OwnerUserId,
    tp.OwnerDisplayName,
    tp.LastActivityDate,
    tp.CommentCount,
    tp.AnswerCount,
    tp.FavoriteCount,
    tp.ContentLicense,
    tr.tag,
    tr.tag_rank,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate AS UserLastAccess
  FROM TopPosts tp
  LEFT JOIN UnnestTags(tp.Tags) AS t(tag) ON TRUE
  LEFT JOIN TagRank tr ON tr.tag = t.tag
  LEFT JOIN Users u ON u.Id = tp.OwnerUserId
),
-- Helper to split tags into rows (PostType 1 specific)
UnnestTags AS (
  SELECT
    p.Id AS PostId,
    unnest(string_to_array(p.Tags, '><')) AS tag
  FROM Posts p
  WHERE p.PostTypeId = 1
),
-- Correlated subquery: recent related posts via PostLinks
Related AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    pl.LinkTypeId,
    pl.CreationDate
  FROM PostLinks pl
  WHERE pl.LinkTypeId IN (1,3) -- Linked or Duplicate
),
-- Windowed window over related posts per post
RelatedWindow AS (
  SELECT
    r.PostId,
    r.RelatedPostId,
    r.LinkTypeId,
    r.CreationDate,
    ROW_NUMBER() OVER (PARTITION BY r.PostId ORDER BY r.CreationDate DESC) AS rn
  FROM Related r
),
Final AS (
  SELECT
    e.PostId,
    e.Title,
    e.Tags,
    e.CreationDate,
    e.Score,
    e.ViewCount,
    e.OwnerUserId,
    e.OwnerDisplayName,
    e.LastActivityDate,
    e.CommentCount,
    e.AnswerCount,
    e.FavoriteCount,
    e.ContentLicense,
    e.tag,
    e.tag_rank,
    e.Reputation,
    e.UserCreationDate,
    e.UserLastAccess,
    rw.RelatedPostId,
    rw.LinkTypeId,
    rw.CreationDate AS RelatedCreationDate
  FROM Enriched e
  LEFT JOIN RelatedWindow rw ON rw.PostId = e.PostId AND rw.rn = 1
  WHERE e.rn_by_type = 1
)
SELECT
  PostId,
  Title,
  Tags,
  CreationDate,
  Score,
  ViewCount,
  OwnerUserId,
  OwnerDisplayName,
  LastActivityDate,
  CommentCount,
  AnswerCount,
  FavoriteCount,
  ContentLicense,
  tag,
  tag_rank,
  Reputation,
  UserCreationDate,
  UserLastAccess,
  RelatedPostId,
  LinkTypeId,
  RelatedCreationDate
FROM Final
ORDER BY Score DESC NULLS LAST, ViewCount DESC NULLS LAST
LIMIT 200;
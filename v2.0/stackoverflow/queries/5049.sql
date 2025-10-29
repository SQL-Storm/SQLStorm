-- {"query": "5049.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1009}
WITH recent_comments AS (
  SELECT
    c.PostId,
    c.Id AS CommentId,
    c.Score AS CommentScore,
    c.Text AS CommentText,
    c.CreationDate AS CommentDate,
    u.Reputation AS UserReputation,
    u.DisplayName AS UserDisplayName,
    ROW_NUMBER() OVER (PARTITION BY c.PostId ORDER BY c.CreationDate DESC) AS rn
  FROM Comments c
  JOIN Users u ON c.UserId = u.Id
),
qualified_posts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.AnswerCount,
    p.PostTypeId,
    p.FavoriteCount,
    p.Body,
    p.ParentId,
    p.AcceptedAnswerId,
    p.LastEditorUserId,
    p.LastEditDate,
    p.LastEditorDisplayName,
    p.OwnerDisplayName
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions only
    AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '180 days')
),
tags_expansion AS (
  SELECT
    qp.PostId,
    TRIM(t.tag) AS tag
  FROM qualified_posts qp,
  LATERAL (
    SELECT value AS tag
    FROM (
      -- split tags like '<tag1><tag2>' into rows; emulate STRING_SPLIT
      SELECT regexp_split_to_table( regexp_replace(qp.Tags, '^<|>$', '', 'g'), '><') AS value
    ) s
  ) t
),
tag_agg AS (
  SELECT
    t.PostId,
    COUNT(*) AS TagCount
  FROM tags_expansion t
  GROUP BY t.PostId
),
correlated_sub AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.Tags,
    rp.OwnerUserId,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.Score,
    rp.ViewCount,
    rp.CommentCount,
    rp.AnswerCount,
    rp.FavoriteCount,
    rp.Body,
    rp.ParentId,
    rp.AcceptedAnswerId,
    rp.LastEditorUserId,
    rp.LastEditDate,
    rp.LastEditorDisplayName,
    rp.OwnerDisplayName,
    ca.CommentId AS LastCommentId,
    ca.CommentDate AS LastCommentDate,
    ca.CommentText AS LastCommentText,
    ca.CommentScore AS LastCommentScore
  FROM qualified_posts rp
  LEFT JOIN (
    SELECT *
    FROM recent_comments
    WHERE rn = 1
  ) ca ON ca.PostId = rp.PostId
),
combined AS (
  SELECT
    cs.PostId,
    cs.Title,
    cs.Tags,
    cs.OwnerUserId,
    cs.CreationDate,
    cs.LastActivityDate,
    cs.Score,
    cs.ViewCount,
    cs.CommentCount,
    cs.AnswerCount,
    cs.FavoriteCount,
    cs.Body,
    cs.ParentId,
    cs.AcceptedAnswerId,
    cs.LastEditorUserId,
    cs.LastEditDate,
    cs.LastEditorDisplayName,
    cs.OwnerDisplayName,
    te.TagCount,
    ca.LastCommentId,
    ca.LastCommentDate,
    ca.LastCommentText,
    ca.LastCommentScore
  FROM tag_agg te
  JOIN correlated_sub cs ON cs.PostId = te.PostId
  LEFT JOIN correlated_sub ca ON ca.PostId = te.PostId
),
windowed AS (
  SELECT
    PostId,
    Title,
    Tags,
    OwnerUserId,
    CreationDate,
    LastActivityDate,
    Score,
    ViewCount,
    CommentCount,
    AnswerCount,
    FavoriteCount,
    Body,
    ParentId,
    AcceptedAnswerId,
    LastEditorUserId,
    LastEditDate,
    LastEditorDisplayName,
    OwnerDisplayName,
    TagCount,
    LastCommentId,
    LastCommentDate,
    LastCommentText,
    LastCommentScore,
    ROW_NUMBER() OVER (
      PARTITION BY OwnerUserId
      ORDER BY Score DESC, LastActivityDate DESC
    ) AS rn_owner
  FROM combined
)
SELECT
  w.PostId,
  w.Title,
  w.Tags,
  w.OwnerUserId,
  w.OwnerDisplayName,
  w.CreationDate,
  w.LastActivityDate,
  w.Score,
  w.ViewCount,
  w.CommentCount,
  w.AnswerCount,
  w.FavoriteCount,
  w.Body,
  w.ParentId,
  w.AcceptedAnswerId,
  w.LastEditorUserId,
  w.LastEditDate,
  w.LastEditorDisplayName,
  w.TagCount,
  w.LastCommentId,
  w.LastCommentDate,
  w.LastCommentText,
  w.LastCommentScore
FROM windowed w
WHERE w.rn_owner <= 3
ORDER BY w.OwnerUserId, w.Score DESC, w.LastActivityDate DESC;
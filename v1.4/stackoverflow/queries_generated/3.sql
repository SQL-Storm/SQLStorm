-- {"query": "3.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1063} 
WITH
recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.AnswerCount,
    p.LastActivityDate,
    p.PostTypeId,
    p.FavoriteCount
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.CreationDate >= NOW() - INTERVAL '90 days'
),
top_tags AS (
  SELECT
    UNNEST(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName,
    p.Id AS PostId
  FROM Posts p
  WHERE p.PostTypeId = 1
),
tag_score AS (
  SELECT
    t.TagName,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) - SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS NetScore
  FROM top_tags t
  LEFT JOIN Votes v ON v.PostId = t.PostId
  GROUP BY t.TagName
),
tag_stats AS (
  SELECT
    ts.TagName,
    ts.Upvotes,
    ts.Downvotes,
    ts.NetScore,
    (SELECT COUNT(*) FROM Posts p WHERE p.PostTypeId = 1 AND p.Tags LIKE '%' || ts.TagName || '%') AS PostCountWithTag
  FROM tag_score ts
),
author_activity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(p.Id) AS PostsCreated,
    SUM(p.ViewCount) AS TotalViews,
    SUM(p.Score) AS TotalScore,
    MAX(p.CreationDate) AS LastPostDate
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
  GROUP BY u.Id, u.DisplayName
),
recent_activities AS (
  SELECT
    q.PostId,
    q.Title,
    q.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    q.CreationDate,
    q.Score AS PostScore,
    q.ViewCount,
    q.CommentCount,
    q.AnswerCount,
    q.LastActivityDate,
    a.TotalViews AS AuthorTotalViews,
    a.TotalScore AS AuthorTotalScore,
    a.PostsCreated
  FROM recent_questions q
  LEFT JOIN author_activity a ON a.UserId = q.OwnerUserId
  LEFT JOIN Users u ON u.Id = q.OwnerUserId
),
latest_edit_history AS (
  SELECT
    ph.PostId,
    ph.UserId AS EditorUserId,
    ph.CreationDate AS EditDate,
    ph.Comment AS EditComment,
    ph.Text AS EditText,
    ph.RevisionGUID
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (4,5,6) -- edits to title/body/tags
),
complex_calculations AS (
  SELECT
    ra.PostId,
    ra.Title,
    ra.OwnerUserId,
    ra.OwnerDisplayName,
    ra.CreationDate,
    ra.PostScore,
    ra.ViewCount,
    ra.CommentCount,
    ra.AnswerCount,
    ra.LastActivityDate,
    lc.NetScore,
    lc.Upvotes - lc.Downvotes AS NetVoteSlope,
    le.EditDate,
    le.EditComment
  FROM recent_activities ra
  LEFT JOIN tag_stats lc ON (SELECT unnest(string_to_array(substr(ra.Tags, 2, length(ra.Tags)-2), '><')) ) IS NOT NULL
  LEFT JOIN latest_edit_history le ON le.PostId = ra.PostId
)
SELECT
  pc.PostId,
  pc.Title,
  pc.OwnerDisplayName AS Owner,
  pc.CreationDate,
  pc.PostScore,
  pc.ViewCount,
  pc.CommentCount,
  pc.AnswerCount,
  pc.LastActivityDate,
  ps.TagName,
  ps.Upvotes AS TagUpvotes,
  ps.Downvotes AS TagDownvotes,
  ps.NetScore AS TagNetScore,
  a.AuthorTotalViews,
  a.AuthorTotalScore,
  a.PostsCreated,
  le.EditDate,
  le.EditComment
FROM complex_calculations pc
LEFT JOIN (
  SELECT
    t.TagName,
    t.PostId
  FROM top_tags t
) AS ttags ON true
LEFT JOIN tag_stats ps ON ps.TagName = ttags.TagName
LEFT JOIN author_activity a ON a.UserId = pc.OwnerUserId
LEFT JOIN latest_edit_history le ON le.PostId = pc.PostId
WHERE
  pc.PostScore IS NOT NULL
ORDER BY
  pc.LastActivityDate DESC,
  pc.ViewCount DESC
LIMIT 200;
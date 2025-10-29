-- {"query": "5697.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1068} 
WITH recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    u.DisplayName AS OwnerName,
    p.LastActivityDate,
    p.CommentCount,
    p.FavoriteCount,
    p.AcceptedAnswerId,
    p.AnswerCount
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= NOW() - INTERVAL '60 days'
),
tag_activity AS (
  SELECT
    t.TagName,
    COUNT(*) AS tag_posts,
    AVG(p.Score) AS avg_score,
    MAX(p.ViewCount) AS max_views
  FROM recent_questions rq
  CROSS APPLY (
    SELECT unnest(string_to_array(substr(rq.Tags, 2, length(rq.Tags)-2), '><')) AS TagName
  ) AS t
  GROUP BY t.TagName
),
top_tags AS (
  SELECT
    TagName,
    tag_posts,
    avg_score,
    max_views
  FROM tag_activity
  ORDER BY tag_posts DESC, avg_score DESC
  LIMIT 5
),
recent_comments AS (
  SELECT
    c.Id AS CommentId,
    c.PostId,
    c.UserId,
    c.Text,
    c.CreationDate,
    c.Score,
    cu.DisplayName AS CommentUser
  FROM Comments c
  LEFT JOIN Users cu ON c.UserId = cu.Id
  WHERE c.CreationDate >= NOW() - INTERVAL '14 days'
),
recent_votes AS (
  SELECT
    v.PostId,
    v.VoteTypeId,
    v.UserId,
    v.CreationDate
  FROM Votes v
  WHERE v.CreationDate >= NOW() - INTERVAL '14 days'
),
complex_post_summary AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.ViewCount,
    p.Score,
    p.CommentCount,
    p.FavoriteCount,
    p.OwnerUserId,
    u.DisplayName AS OwnerName,
    (SELECT COUNT(*) FROM Posts pr WHERE pr.ParentId = p.Id) AS ChildCount,
    (SELECT STRING_AGG(ct.Text, ' | ' ORDER BY ct.CreationDate) 
     FROM Comments ct WHERE ct.PostId = p.Id) AS AllComments,
    (SELECT COUNT(*) FROM Votes vv WHERE vv.PostId = p.Id AND vv.VoteTypeId = 2) AS UpVotesForPost,
    (SELECT COUNT(*) FROM Votes vv WHERE vv.PostId = p.Id AND vv.VoteTypeId = 3) AS DownVotesForPost
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
),
final_union AS (
  SELECT
    p.PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.ViewCount,
    p.Score,
    p.CommentCount,
    p.FavoriteCount,
    p.OwnerUserId,
    p.OwnerName,
    p.ChildCount,
    p.AllComments,
    p.UpVotesForPost,
    p.DownVotesForPost
  FROM complex_post_summary p

  UNION ALL

  SELECT
    (* synthetic placeholder to keep structure in exotic queries *) -1 AS PostId,
    NULL AS Title,
    NULL AS Tags,
    NULL AS CreationDate,
    NULL AS LastActivityDate,
    NULL AS ViewCount,
    NULL AS Score,
    NULL AS CommentCount,
    NULL AS FavoriteCount,
    NULL AS OwnerUserId,
    NULL AS OwnerName,
    NULL AS ChildCount,
    NULL AS AllComments,
    NULL AS UpVotesForPost,
    NULL AS DownVotesForPost
)
SELECT
  f.PostId,
  f.Title,
  f.Tags,
  f.CreationDate,
  f.LastActivityDate,
  f.ViewCount,
  f.Score,
  f.CommentCount,
  f.FavoriteCount,
  f.OwnerUserId,
  f.OwnerName,
  f.ChildCount,
  f.AllComments,
  f.UpVotesForPost,
  f.DownVotesForPost,
  rt.TagName AS TopTag,
  rt.tag_posts,
  rt.avg_score AS TopTagAvgScore,
  rt.max_views AS TopTagMaxViews,
  qc.CommentId AS RecentCommentId,
  qc.CommentUser AS RecentCommentUser,
  qc.Text AS RecentCommentText,
  qv.VoteTypeId AS RecentVoteType,
  qv.CreationDate AS RecentVoteDate
FROM final_union f
LEFT JOIN top_tags rt ON POSITION(rt.TagName IN f.Tags) > 0
LEFT JOIN recent_comments qc ON qc.PostId = f.PostId
LEFT JOIN recent_votes qv ON qv.PostId = f.PostId
ORDER BY f.LastActivityDate DESC NULLS LAST
LIMIT 100;
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
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '60 days'
),
tag_activity AS (
  SELECT
    t.TagName,
    COUNT(*) AS tag_posts,
    AVG(rq.Score) AS avg_score,
    MAX(rq.ViewCount) AS max_views
  FROM recent_questions rq,
       LATERAL (
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
  WHERE c.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '14 days'
),
recent_votes AS (
  SELECT
    v.PostId,
    v.VoteTypeId,
    v.UserId,
    v.CreationDate
  FROM Votes v
  WHERE v.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '14 days'
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
    -1 AS PostId,
    NULL AS Title,
    NULL AS Tags,
    CAST(NULL AS timestamp) AS CreationDate,
    CAST(NULL AS timestamp) AS LastActivityDate,
    CAST(NULL AS bigint) AS ViewCount,
    CAST(NULL AS integer) AS Score,
    CAST(NULL AS integer) AS CommentCount,
    CAST(NULL AS integer) AS FavoriteCount,
    CAST(NULL AS bigint) AS OwnerUserId,
    CAST(NULL AS text) AS OwnerName,
    CAST(NULL AS integer) AS ChildCount,
    CAST(NULL AS text) AS AllComments,
    CAST(NULL AS integer) AS UpVotesForPost,
    CAST(NULL AS integer) AS DownVotesForPost
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
LEFT JOIN top_tags rt ON POSITION(rt.TagName IN COALESCE(f.Tags, '')) > 0
LEFT JOIN recent_comments qc ON qc.PostId = f.PostId
LEFT JOIN recent_votes qv ON qv.PostId = f.PostId
GROUP BY
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
  rt.TagName,
  rt.tag_posts,
  rt.avg_score,
  rt.max_views,
  qc.CommentId,
  qc.CommentUser,
  qc.Text,
  qv.VoteTypeId,
  qv.CreationDate
ORDER BY f.LastActivityDate DESC NULLS LAST
LIMIT 100;
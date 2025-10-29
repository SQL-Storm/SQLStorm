-- {"query": "5976.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 689} 
WITH recent_posts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.CreationDate,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.ClosedDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.Body,
    p.ContentLicense
  FROM Posts p
  WHERE p.CreationDate >= NOW() - INTERVAL '30 days'
),
tag_aggregate AS (
  SELECT
    t.TagName,
    COUNT(*) AS posts_with_tag,
    AVG(p.Score) AS avg_score_per_post,
    SUM(p.ViewCount) AS total_views
  FROM Tags t
  JOIN Posts p ON p.Id = t.ExcerptPostId
  WHERE t.TagName IS NOT NULL
  GROUP BY t.TagName
  HAVING COUNT(*) > 5
),
recent_comments AS (
  SELECT
    c.PostId,
    c.Id AS CommentId,
    c.UserId,
    c.Score,
    c.CreationDate,
    c.Text,
    c.UserDisplayName
  FROM Comments c
  WHERE c.CreationDate >= NOW() - INTERVAL '14 days'
),
top_voted AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) - SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS NetVotes
  FROM Votes v
  GROUP BY v.PostId
),
author_activity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(p.Id) AS posts_created,
    MAX(p.CreationDate) AS last_post_date,
    SUM(p.Score) AS total_score
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName
)
SELECT
  rp.PostId,
  rp.Title,
  rp.Tags,
  rp.Score AS PostScore,
  rp.ViewCount,
  ra.NetVotes,
  ta.avg_score_per_post,
  ta.total_views,
  cc.CommentId,
  cc.Text AS RecentCommentText,
  aa.UserId AS AuthorId,
  au.DisplayName AS AuthorName,
  aa.posts_created,
  aa.total_score AS AuthorTotalScore,
  tga.TagName,
  tga.posts_with_tag
FROM recent_posts rp
LEFT JOIN top_voted ra ON ra.PostId = rp.Id
LEFT JOIN author_activity aa ON aa.UserId = rp.OwnerUserId
LEFT JOIN recent_comments cc ON cc.PostId = rp.Id
LEFT JOIN tag_aggregate tga ON 1=1
LEFT JOIN (
  SELECT p.Id, p.Title, p.Tags, p.OwnerUserId
  FROM Posts p
) au ON au.OwnerUserId = rp.OwnerUserId
ORDER BY rp.LastActivityDate DESC, ra.NetVotes DESC
LIMIT 100;
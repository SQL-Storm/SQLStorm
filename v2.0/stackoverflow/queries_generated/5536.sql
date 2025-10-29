-- {"query": "5536.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1017} 
WITH recent_user_activity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.AboutMe,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl,
    u.EmailHash,
    u.AccountId,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY u.LastAccessDate DESC) AS rn
  FROM Users u
),
top_posts AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.AcceptedAnswerId,
    p.PostTypeId,
    p.LastActivityDate,
    p.ParentId,
    p.Body,
    p.LastEditorUserId,
    p.LastEditDate,
    p.OwnerDisplayName,
    p.FavoriteCount,
    p.ContentLicense,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn_post_by_user
  FROM Posts p
  WHERE p.LastActivityDate > NOW() - INTERVAL '365 days'
    OR p.CreationDate > NOW() - INTERVAL '365 days'
),
recent_comments AS (
  SELECT
    c.Id AS CommentId,
    c.PostId,
    c.UserId,
    c.Text,
    c.CreationDate,
    c.Score,
    c.UserDisplayName,
    c.ContentLicense,
    ROW_NUMBER() OVER (PARTITION BY c.PostId ORDER BY c.CreationDate DESC) AS rn_comment
  FROM Comments c
  WHERE c.CreationDate > NOW() - INTERVAL '365 days'
),
 tagging AS (
  SELECT
    t.Id,
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId,
    t.IsModeratorOnly,
    t.IsRequired
  FROM Tags t
  WHERE t.Count > 5
),
 recent_votes AS (
  SELECT
    v.PostId,
    v.VoteTypeId,
    v.UserId,
    v.CreationDate,
    v.BountyAmount,
    ROW_NUMBER() OVER (PARTITION BY v.PostId ORDER BY v.CreationDate DESC) AS rn_vote
  FROM Votes v
  WHERE v.CreationDate > NOW() - INTERVAL '180 days'
),
 post_links AS (
  SELECT
    pl.Id,
    pl.PostId,
    pl.RelatedPostId,
    pl.LinkTypeId,
    pl.CreationDate
  FROM PostLinks pl
  WHERE pl.LinkTypeId IN (1, 3)
),
 busted AS (
  SELECT
    bp.PostId,
    bp.RelatedPostId,
    bl.Name AS LinkTypeName
  FROM post_links bp
  JOIN LinkTypes bl ON bl.Id = bp.LinkTypeId
  WHERE bl.Name IN ('Linked', 'Duplicate')
)
SELECT
  up.UserId,
  up.DisplayName AS UserDisplayName,
  up.Reputation,
  up.CreationDate AS UserCreationDate,
  up.LastAccessDate,
  up.Location,
  up.AboutMe,
  up.Views,
  up.UpVotes,
  up.DownVotes,
  up.ProfileImageUrl,
  up.EmailHash,
  up.AccountId,
  rp.PostId,
  rp.Title,
  rp.Tags,
  rp.CreationDate AS PostCreationDate,
  rp.Score AS PostScore,
  rp.ViewCount,
  rp.CommentCount,
  rp.AcceptedAnswerId,
  rp.PostTypeId,
  rp.LastActivityDate AS PostLastActivityDate,
  rp.ParentId,
  rp.Body,
  rp.LastEditorUserId,
  rp.LastEditDate,
  rp.OwnerDisplayName,
  rp.FavoriteCount,
  rp.ContentLicense,
  ce.CommentId AS LatestCommentId,
  ce.Text AS LatestCommentText,
  ce.CreationDate AS LatestCommentDate,
  vy.VoteTypeId AS LatestVoteTypeId,
  vy.CreationDate AS LatestVoteDate,
  vy.BountyAmount,
  pb.RelatedPostId AS LinkedPostId,
  l.Name AS LinkedTypeName
FROM recent_user_activity up
LEFT JOIN top_posts rp
  ON rp.OwnerUserId = up.Id
LEFT JOIN recent_comments ce
  ON ce.PostId = rp.PostId
LEFT JOIN recent_votes vy
  ON vy.PostId = rp.PostId AND vy.rn_vote = 1
LEFT JOIN busted pb
  ON pb.PostId = rp.PostId
LEFT JOIN LinkTypes l ON l.Id = pb.LinkTypeId
WHERE up.rn = 1
ORDER BY up.Reputation DESC, rp.CreationDate DESC
LIMIT 100;
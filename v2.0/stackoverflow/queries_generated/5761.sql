-- {"query": "5761.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 951} 
WITH
rich_posts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.Body,
    p.CreationDate,
    p.OwnerUserId,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.LastActivityDate,
    p.CommentCount,
    p.AcceptedAnswerId,
    p.ParentId,
    p.LastEditDate,
    p.LastEditorUserId,
    p.LastEditorDisplayName,
    p.FavoriteCount,
    p.ContentLicense
  FROM Posts p
  WHERE p.PostTypeId IN (1,2) -- Questions and Answers
),
author_stats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.Location,
    u.WebsiteUrl
  FROM Users u
),
tag_info AS (
  SELECT
    t.Id AS TagId,
    t.TagName,
    t.Count,
    t.ExcerptPostId
  FROM Tags t
),
recent_comments AS (
  SELECT
    c.PostId,
    c.Id AS CommentId,
    c.UserId AS CommentUserId,
    c.UserDisplayName,
    c.Text,
    c.CreationDate,
    c.Score,
    c.ContentLicense
  FROM Comments c
  WHERE c.CreationDate > (CURRENT_DATE - INTERVAL '180 days')
),
post_votes AS (
  SELECT
    v.PostId,
    v.VoteTypeId,
    v.UserId,
    v.CreationDate,
    v.BountyAmount
  FROM Votes v
  WHERE v.VoteTypeId IN (2,3,10,11,12,14,15,16) -- relevant activity types
)
SELECT
  rp.PostId,
  rp.PostTypeId,
  rp.Title,
  rp.Tags,
  rp.Score AS PostScore,
  rp.ViewCount,
  rp.CreationDate AS PostCreationDate,
  rp.LastActivityDate,
  COALESCE(a.DisplayName, rp.OwnerDisplayName) AS PostAuthor,
  a.Reputation AS AuthorReputation,
  COALESCE(SUM(CASE WHEN pv.VoteTypeId = 2 THEN 1 END) OVER (PARTITION BY rp.PostId), 0) AS UpVotesFromVotes,
  COALESCE(SUM(CASE WHEN pv.VoteTypeId = 3 THEN 1 END) OVER (PARTITION BY rp.PostId), 0) AS DownVotesFromVotes,
  COUNT(DISTINCT lc.CommentId) AS CommentCount,
  STRING_AGG(DISTINCT tc.TagName, ',') OVER (PARTITION BY rp.PostId) AS RelatedTags,
  ARRAY_AGG(DISTINCT qc.Text) FILTER (WHERE qc.Text IS NOT NULL) OVER (PARTITION BY rp.PostId) AS RecentCommentSnippets,
  CASE
    WHEN rp.PostTypeId = 1 THEN 'Question'
    ELSE 'Answer'
  END AS PostKind,
  CASE
    WHEN rp.AcceptedAnswerId IS NOT NULL THEN TRUE
    ELSE FALSE
  END AS HasAcceptedAnswer,
  CASE
    WHEN rp.ParentId IS NOT NULL THEN rp.ParentId
    ELSE NULL
  END AS ParentPostId,
  jsonb_build_object(
      'LastEditor', rp.LastEditorDisplayName,
      'LastEditDate', rp.LastEditDate
    ) AS EditMeta
FROM
  rich_posts rp
  LEFT JOIN author_stats a ON rp.OwnerUserId = a.UserId
  LEFT JOIN post_votes pv ON rp.PostId = pv.PostId
  LEFT JOIN recent_comments qc ON rp.PostId = qc.PostId
  LEFT JOIN post_links pl ON rp.PostId = pl.PostId
  LEFT JOIN TagInfo ti ON rp.Id = ti.ExcerptPostId
  LEFT JOIN post_tags pt ON rp.PostId = pt.PostId
  LEFT JOIN Tags t ON t.Id = pt.TagId
  LEFT JOIN Comments lc ON lc.PostId = rp.PostId AND lc.Id = lc.Id
GROUP BY
  rp.PostId, rp.PostTypeId, rp.Title, rp.Tags, rp.Score, rp.ViewCount,
  rp.CreationDate, rp.LastActivityDate, a.DisplayName, a.Reputation,
  rp.OwnerUserId, rp.AcceptedAnswerId, rp.ParentId, rp.LastEditorDisplayName,
  rp.LastEditDate, rp.ContentLicense;
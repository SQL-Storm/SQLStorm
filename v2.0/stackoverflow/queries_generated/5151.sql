-- {"query": "5151.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 944} 
WITH top_users AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u creation_date := u.CreationDate,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.Id) AS rn
  FROM Users u
),
pop_posts AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastActivityDate,
    p.PostTypeId,
    p.AcceptedAnswerId,
    p.ParentId,
    p.CommentCount,
    p.FavoriteCount,
    p.Body,
    p.LastEditorDisplayName,
    p.LastEditDate,
    p.OwnerDisplayName,
    p.ContentLicense
  FROM Posts p
  LEFT JOIN LATERAL (
    SELECT 1
  ) AS d ON true
),
recent_comments AS (
  SELECT
    c.Id AS CommentId,
    c.PostId,
    c.UserId,
    c.Text,
    c.CreationDate,
    c.Score,
    c.UserDisplayName
  FROM Comments c
  WHERE c.CreationDate > NOW() - INTERVAL '90 days'
),
recent_votes AS (
  SELECT
    v.Id AS VoteId,
    v.PostId,
    v.VoteTypeId,
    v.UserId,
    v.CreationDate,
    v.BountyAmount
  FROM Votes v
  WHERE v.CreationDate > NOW() - INTERVAL '90 days'
),
tag_activity AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId,
    t.IsModeratorOnly
  FROM Tags t
  WHERE t.IsModeratorOnly = 0
),
complex_combined AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName AS UserName,
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.CreationDate AS PostCreationDate,
    p.LastActivityDate,
    p.PostTypeId,
    COALESCE(p.AcceptedAnswerId, 0) AS AcceptedAnswerId,
    p.ParentId,
    p.CommentCount,
    p.FavoriteCount,
    p.Body,
    p.LastEditorDisplayName,
    p.LastEditDate,
    p.OwnerDisplayName,
    p.ContentLicense,
    ARRAY_AGG(DISTINCT tc.TagName) AS TagsList,
    COUNT(DISTINCT rc.CommentId) AS RecentCommentCount,
    SUM(CASE WHEN rv.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesLast90d,
    SUM(CASE WHEN rv.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesLast90d
  FROM Posts p
  JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN UNNEST(string_to_array(p.Tags, '><')) AS t2(tag) ON true
  LEFT JOIN tag_activity tc ON lower(tc.TagName) = lower(t2.tag)
  LEFT JOIN recent_comments rc ON rc.PostId = p.Id
  LEFT JOIN recent_votes rv ON rv.PostId = p.Id
  GROUP BY
    u.Id, u.DisplayName,
    p.Id, p.Title, p.Tags, p.Score, p.ViewCount, p.CreationDate, p.LastActivityDate,
    p.PostTypeId, p.AcceptedAnswerId, p.ParentId, p.CommentCount, p.FavoriteCount,
    p.Body, p.LastEditorDisplayName, p.LastEditDate, p.OwnerDisplayName, p.ContentLicense
)
SELECT
  cu.UserName,
  cu.PostId,
  cu.Title,
  cu.TagsList,
  cu.Score,
  cu.ViewCount,
  cu.PostCreationDate,
  cu.LastActivityDate,
  cu.PostTypeId,
  cu.AcceptedAnswerId,
  cu.ParentId,
  cu.CommentCount,
  cu.FavoriteCount,
  cu.Body,
  cu.LastEditorDisplayName,
  cu.LastEditDate,
  cu.OwnerDisplayName,
  cu.ContentLicense,
  cu.RecentCommentCount,
  cu.UpvotesLast90d,
  cu.DownvotesLast90d,
  hu.Reputation,
  hu.creation_date
FROM complex_combined cu
LEFT JOIN top_users hu ON cu.UserId = hu.UserId
ORDER BY cu.LastActivityDate DESC
LIMIT 100;
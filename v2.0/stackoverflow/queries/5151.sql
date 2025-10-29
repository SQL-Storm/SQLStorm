-- {"query": "5151.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 944}
WITH top_users AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS creation_date,
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
  WHERE c.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '90' DAY
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
  WHERE v.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '90' DAY
),
tag_activity AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId,
    t.IsModeratorOnly
  FROM Tags t
  WHERE t.IsModeratorOnly = FALSE
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
  LEFT JOIN LATERAL (
    SELECT regexp_split_to_table(TRIM(BOTH '<>' FROM p.Tags), '><') AS tag
  ) t2 ON true
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
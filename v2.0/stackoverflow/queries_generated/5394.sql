-- {"query": "5394.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 760} 
WITH RecentActivePosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.Body,
    p.ContentLicense,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    u.CreationDate AS OwnerCreationDate,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
    MAX(CASE WHEN vt.Name ILIKE 'AcceptedByOriginator' THEN 1 ELSE 0 END) AS HasAccepted
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  WHERE p.LastActivityDate >= NOW() - INTERVAL '30 days'
  GROUP BY
    p.Id, p.PostTypeId, p.OwnerUserId, p.Title, p.Tags,
    p.CreationDate, p.LastActivityDate, p.Score, p.ViewCount,
    p.AnswerCount, p.CommentCount, p.FavoriteCount, p.Body,
    p.ContentLicense, u.DisplayName, u.Reputation, u.CreationDate
),
TagRelationships AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId,
    CASE
      WHEN t.IsModeratorOnly = 1 THEN true
      ELSE false
    END AS IsModOnly
  FROM Tags t
),
CrossJoinStats AS (
  SELECT
    par.PostId,
    par.PostTypeId,
    par.OwnerUserId,
    par.Title,
    par.Tags,
    par.CreationDate,
    par.LastActivityDate,
    par.Score,
    par.ViewCount,
    par.AnswerCount,
    par.CommentCount,
    par.FavoriteCount,
    par.Body,
    par.ContentLicense,
    par.OwnerDisplayName,
    par.Reputation,
    par.OwnerCreationDate,
    par.UpVotes,
    par.DownVotes,
    par.HasAccepted,
    t.TagName,
    t.Count AS TagCount,
    t.IsModOnly
  FROM RecentActivePosts par
  LEFT JOIN LATERAL (
    SELECT unnest(string_to_array(substring(par.Tags, 2, length(par.Tags)-2), '><')) AS TagName
  ) AS tmap ON true
  LEFT JOIN TagRelationships t ON t.TagName = tmap.TagName
)
SELECT
  cjs.PostId,
  cjs.PostTypeId,
  cjs.OwnerUserId,
  cjs.Title,
  cjs.Tags,
  cjs.CreationDate,
  cjs.LastActivityDate,
  cjs.Score,
  cjs.ViewCount,
  cjs.AnswerCount,
  cjs.CommentCount,
  cjs.FavoriteCount,
  cjs.Body,
  cjs.ContentLicense,
  cjs.OwnerDisplayName,
  cjs.Reputation,
  cjs.OwnerCreationDate,
  cjs.UpVotes,
  cjs.DownVotes,
  cjs.HasAccepted,
  cjs.TagName,
  cjs.TagCount,
  cjs.IsModOnly
FROM CrossJoinStats cjs
ORDER BY cjs.LastActivityDate DESC, cjs.Score DESC
LIMIT 200;
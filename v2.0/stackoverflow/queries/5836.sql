-- {"query": "5836.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 963}
WITH RankedPosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.OwnerUserId,
    p.LastActivityDate,
    p.FavoriteCount,
    p.CommentCount,
    p.Body,
    p.AcceptedAnswerId,
    p.ParentId,
    p.LastEditDate,
    p.ContentLicense,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    u.CreationDate AS OwnerCreationDate,
    u.LastAccessDate AS OwnerLastAccessDate,
    CASE WHEN v.Id IS NULL THEN 0 ELSE 1 END AS HasVotes,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY p.Score DESC, p.ViewCount DESC, p.LastActivityDate DESC
    ) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId IN (2,3)
  WHERE (p.OwnerUserId IS NULL) OR (p.OwnerUserId = 0) OR (u.AccountId IS NULL) OR (u.AccountId = 0)
),
Filtered AS (
  SELECT *
  FROM RankedPosts
  WHERE PostTypeId IN (1,2) -- Questions and Answers
    AND rn <= 200
),
Aggregated AS (
  SELECT
    p.PostId,
    p.PostTypeId,
    p.Title,
    p.OwnerDisplayName,
    p.OwnerUserId,
    p.Reputation,
    p.CreationDate,
    p.LastActivityDate,
    p.ViewCount,
    p.Score,
    p.Tags,
    p.Body,
    p.CommentCount,
    p.FavoriteCount,
    p.AcceptedAnswerId,
    p.ParentId,
    p.LastEditDate,
    p.ContentLicense,
    p.HasVotes,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.PostId) AS CommentCountTotal,
    (SELECT STRING_AGG(CAST(v2.Id AS varchar), ',') FROM Votes v2 WHERE v2.PostId = p.PostId) AS VoteIdList
  FROM Filtered p
  GROUP BY
    p.PostId, p.PostTypeId, p.Title, p.OwnerDisplayName, p.OwnerUserId, p.Reputation,
    p.CreationDate, p.LastActivityDate, p.ViewCount, p.Score, p.Tags, p.Body,
    p.CommentCount, p.FavoriteCount, p.AcceptedAnswerId, p.ParentId, p.LastEditDate,
    p.ContentLicense, p.HasVotes
),
Neighbors AS (
  SELECT
    a.PostId,
    a.PostTypeId,
    a.Title,
    a.OwnerDisplayName,
    a.OwnerUserId,
    a.Reputation,
    a.CreationDate,
    a.LastActivityDate,
    a.ViewCount,
    a.Score,
    a.Tags,
    a.Body,
    a.CommentCount,
    a.FavoriteCount,
    a.AcceptedAnswerId,
    a.ParentId,
    a.LastEditDate,
    a.ContentLicense,
    a.HasVotes,
    a.CommentCountTotal,
    a.VoteIdList,
    (SELECT COUNT(*) FROM PostLinks pl
     WHERE (pl.PostId = a.PostId OR pl.RelatedPostId = a.PostId)
       AND pl.LinkTypeId IN (1,3)) AS LinkCount
  FROM Aggregated a
  GROUP BY
    a.PostId, a.PostTypeId, a.Title, a.OwnerDisplayName, a.OwnerUserId, a.Reputation,
    a.CreationDate, a.LastActivityDate, a.ViewCount, a.Score, a.Tags, a.Body,
    a.CommentCount, a.FavoriteCount, a.AcceptedAnswerId, a.ParentId, a.LastEditDate,
    a.ContentLicense, a.HasVotes, a.CommentCountTotal, a.VoteIdList
),
Windowed AS (
  SELECT
    n.*,
    ROW_NUMBER() OVER (PARTITION BY n.PostTypeId ORDER BY n.LastActivityDate DESC, n.ViewCount DESC) AS wrow
  FROM Neighbors n
)
SELECT
  w.PostId,
  CASE
    WHEN w.PostTypeId = 1 THEN 'Question'
    WHEN w.PostTypeId = 2 THEN 'Answer'
    ELSE 'Other'
  END AS PostType,
  w.Title,
  w.OwnerDisplayName,
  w.Reputation,
  w.CreationDate,
  w.LastActivityDate,
  w.ViewCount,
  w.Score,
  w.Tags,
  w.Body,
  w.CommentCount,
  w.FavoriteCount,
  w.AcceptedAnswerId,
  w.ParentId,
  w.LastEditDate,
  w.ContentLicense,
  w.HasVotes,
  w.CommentCountTotal,
  w.VoteIdList,
  w.LinkCount,
  COALESCE(w.Score, 0) * 1.0 + COALESCE(w.ViewCount, 0) * 0.01 + COALESCE(w.FavoriteCount, 0) * 2.0 AS EngagementScore,
  w.wrow AS TypeRank
FROM Windowed w
WHERE w.wrow <= 50
ORDER BY w.LastActivityDate DESC, w.Score DESC, w.ViewCount DESC;
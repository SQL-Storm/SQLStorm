-- {"query": "5746.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1389} 
WITH 
RecentActivePosts AS (
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
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.ContentLicense,
    p.OwnerDisplayName,
    p.LastEditorUserId,
    p.LastEditorDisplayName,
    p.LastEditDate,
    p.ParentId,
    p.AcceptedAnswerId,
    p.Body
  FROM Posts p
  WHERE p.CreationDate >= NOW() - INTERVAL '180 days'
),
TopUsers AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.Location,
    u.WebsiteUrl,
    u.AccountId,
    u.ProfileImageUrl,
    u.EmailHash,
    u.AboutMe,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.UpVotes DESC, u.ViewCount DESC) AS rn
  FROM Users u
  WHERE u.Reputation > 0
),
TagStats AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId,
    (SELECT p.Id FROM Posts p WHERE p.Id = t.ExcerptPostId) AS ExcerptPostIdExists,
    (SELECT p.Id FROM Posts p WHERE p.Id = t.WikiPostId) AS WikiPostIdExists
  FROM Tags t
  WHERE t.IsModeratorOnly = 0
),
PostLinksAgg AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    pl.LinkTypeId,
    lt.Name AS LinkTypeName,
    pa.Title AS RelatedTitle,
    pa.CreationDate AS RelatedCreationDate,
    pa.Score AS RelatedScore
  FROM PostLinks pl
  JOIN Posts pa ON pa.Id = pl.RelatedPostId
  JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
  WHERE pl.LinkTypeId IN (1,3) -- Linked or Duplicate
),
VotesAgg AS (
  SELECT
    v.PostId,
    v.VoteTypeId,
    vt.Name AS VoteTypeName,
    v.UserId,
    v.CreationDate,
    v.BountyAmount
  FROM Votes v
  JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
  WHERE v.CreationDate >= NOW() - INTERVAL '90 days'
),
BadgeActivity AS (
  SELECT
    b.UserId,
    b.Name AS BadgeName,
    b.Class,
    b.Date AS BadgeDate,
    b.TagBased,
    ROW_NUMBER() OVER (PARTITION BY b.UserId, b.Name ORDER BY b.Date DESC) AS rn
  FROM Badges b
  WHERE b.Date >= NOW() - INTERVAL '1 year'
),
-- Correlated subquery: for each post, find if it has a recent close/reopen history entry
PostHistoryLatest AS (
  SELECT
    ph.PostId,
    ph.PostHistoryTypeId,
    ph.CreationDate,
    ph.Comment,
    ph.Text,
    ph.UserId,
    ph.RevisionGUID,
    ph.PostHistoryTypeId AS PHT
  FROM PostHistory ph
  JOIN (
    SELECT PostId, MAX(CreationDate) AS maxc
    FROM PostHistory
    GROUP BY PostId
  ) m ON ph.PostId = m.PostId AND ph.CreationDate = m.maxc
)
SELECT
  -- Performance-oriented, heavy mix of constructs
  p.Id AS PostId,
  p.PostTypeId,
  p.Title,
  p.Tags,
  p.CreationDate,
  p.LastActivityDate,
  p.Score,
  p.ViewCount,
  p.CommentCount,
  p.AnswerCount,
  p.FavoriteCount,
  p.ContentLicense,
  p.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  p.LastEditorUserId,
  p.LastEditorDisplayName,
  p.LastEditDate,
  p.ParentId,
  p.AcceptedAnswerId,
  p.Body,
  -- Window function over posts per day bucket
  SUM(p.Score) OVER (PARTITION BY DATE(p.CreationDate)) AS DailyScoreSum,
  -- Subquery: count of comments by post
  (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCountFromComments,
  -- Correlated subquery in select: check if post has a high-reputation author
  (SELECT TOP 1 u2.Reputation
     FROM Users u2
     WHERE u2.Id = p.OwnerUserId
     ORDER BY u2.Reputation DESC) AS TopAuthorReputation,
  -- Set operation emulation: union with a synthetic row for benchmarking
  NULL AS BenchmarkExtraColumn
FROM RecentActivePosts p
LEFT JOIN Users u ON u.Id = p.OwnerUserId
LEFT JOIN PostHistoryLatest ph ON ph.PostId = p.Id
LEFT JOIN TagStats ts ON ts.ExcerptPostIdExists = p.Id OR ts.WikiPostIdExists = p.Id
LEFT JOIN PostLinksAgg pla ON pla.PostId = p.Id
WHERE EXISTS (
  SELECT 1
  FROM VotesAgg va
  WHERE va.PostId = p.Id
    AND va.VoteTypeName IN ('UpMod', 'Favorite', 'AcceptedByOriginator')
)
ORDER BY p.LastActivityDate DESC, p.Score DESC
-- UNION ALL to introduce an additional synthetic benchmark dataset row (outer query using set operation)
UNION ALL
SELECT
  NULL AS PostId,
  NULL AS PostTypeId,
  NULL AS Title,
  NULL AS Tags,
  NULL AS CreationDate,
  NULL AS LastActivityDate,
  NULL AS Score,
  NULL AS ViewCount,
  NULL AS CommentCount,
  NULL AS AnswerCount,
  NULL AS FavoriteCount,
  NULL AS ContentLicense,
  NULL AS OwnerUserId,
  NULL AS OwnerDisplayName,
  NULL AS LastEditorUserId,
  NULL AS LastEditorDisplayName,
  NULL AS LastEditDate,
  NULL AS ParentId,
  NULL AS AcceptedAnswerId,
  NULL AS Body,
  NULL AS DailyScoreSum,
  NULL AS CommentCountFromComments,
  NULL AS TopAuthorReputation,
  NULL AS BenchmarkExtraColumn
FROM (VALUES (1)) AS t(n)
ORDER BY LastActivityDate DESC NULLS LAST
;
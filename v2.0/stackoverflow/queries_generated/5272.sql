-- {"query": "5272.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1146} 
WITH
RecentTargets AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    p.PostTypeId,
    p.AnswerCount,
    p.CommentCount
  FROM Posts p
  WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
),
TopTags AS (
  SELECT
    t.TagName,
    t.Count AS TagCount
  FROM Tags t
  WHERE t.IsModeratorOnly = 0
),
ActiveUsers AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.Location
  FROM Users u
  WHERE u.LastAccessDate > NOW() - INTERVAL '30 days'
),
HeatMap AS (
  SELECT
    r.PostId,
    r.Title,
    r.CreationDate,
    r.Score,
    r.ViewCount,
    r.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    ROW_NUMBER() OVER (PARTITION BY r.OwnerUserId ORDER BY r.Score DESC, r.ViewCount DESC) AS rn
  FROM RecentTargets r
  LEFT JOIN ActiveUsers u ON r.OwnerUserId = u.UserId
),
CorrelatedNotes AS (
  SELECT
    h.PostHistoryTypeId,
    h.PostId,
    h.CreationDate,
    h.UserId,
    h.Comment,
    h.Text
  FROM PostHistory h
  WHERE h.PostHistoryTypeId IN (10, 11, 16, 24) -- close, reopen, community owned, suggested edit
),
LinkGraph AS (
  SELECT
    PL.PostId,
    PL.RelatedPostId,
    PL.LinkTypeId,
    L.Name AS LinkTypeName,
    P1.OwnerUserId AS PostOwnerId,
    P2.OwnerUserId AS RelatedPostOwnerId
  FROM PostLinks PL
  JOIN Posts P1 ON PL.PostId = P1.Id
  JOIN Posts P2 ON PL.RelatedPostId = P2.Id
  JOIN LinkTypes L ON PL.LinkTypeId = L.Id
  WHERE PL.LinkTypeId IN (1, 3)
),
BadgeScore AS (
  SELECT
    b.UserId,
    SUM(CASE WHEN b.Class = 1 THEN 5 WHEN b.Class = 2 THEN 3 ELSE 1 END) AS BadgeValue
  FROM Badges b
  GROUP BY b.UserId
),
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COALESCE(SUM(v.BountyAmount), 0) AS TotalBounty,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpvotesGiven,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownvotesGiven,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 10 THEN 1 ELSE 0 END), 0) AS DeletionsCast
  FROM Users u
  LEFT JOIN Votes v ON v.UserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
)
SELECT
  h.PostId,
  h.Title,
  h.CreationDate,
  h.Score,
  h.ViewCount,
  h.OwnerUserId,
  h.OwnerDisplayName,
  h.PostTypeId,
  h.AnswerCount,
  h.CommentCount,
  hu.DisplayName AS LastEditorDisplayName,
  hu2.DisplayName AS CreatedByDisplayName,
  ARRAY_AGG(DISTINCT tg.TagName) FILTER (WHERE t.TagName IS NOT NULL) AS RelatedTags,
  b.BadgeValue,
  ua.TotalBounty,
  ua.UpvotesGiven,
  ua.DownvotesGiven,
  ua.Dele tionsCast,
  STRING_AGG(CONCAT('Post ', h.PostId, ' by ', hu.DisplayName), ' | ') AS ActivitySummary,
  STRING_AGG(DISTINCT 'Tag:' || t.TagName, ',') OVER () AS ClusterTags,
  COUNT(*) OVER () AS TotalRows
FROM HeatMap h
LEFT JOIN Users hu ON h.OwnerUserId = hu.Id
LEFT JOIN Users hu2 ON h.OwnerUserId = hu2.Id
LEFT JOIN Tags t ON t.Id = CAST(SUBSTRING(h.Tags, 2, LENGTH(h.Tags)-2) AS INT)
LEFT JOIN TagGraph tg ON tg.PostId = h.PostId
LEFT JOIN BadgeScore b ON b.UserId = h.OwnerUserId
LEFT JOIN UserActivity ua ON ua.UserId = h.OwnerUserId
GROUP BY
  h.PostId,
  h.Title,
  h.CreationDate,
  h.Score,
  h.ViewCount,
  h.OwnerUserId,
  h.OwnerDisplayName,
  h.PostTypeId,
  h.AnswerCount,
  h.CommentCount,
  hu.DisplayName,
  hu2.DisplayName,
  b.BadgeValue,
  ua.TotalBounty,
  ua.UpvotesGiven,
  ua.DownvotesGiven,
  ua.Dele tionsCast
ORDER BY h.Score DESC NULLS LAST, h.ViewCount DESC, h.CreationDate DESC
LIMIT 100;
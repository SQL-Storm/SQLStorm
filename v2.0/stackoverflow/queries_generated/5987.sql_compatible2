WITH Agg AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.LastActivityDate,
    p.ContentLicense,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.LastActivityDate DESC, p.Score DESC) AS rn_by_activity
  FROM Posts p
  LEFT JOIN LATERAL (
    SELECT 1 AS dummy
  ) l ON TRUE
),
RecentActivity AS (
  SELECT
    a.PostId,
    a.PostTypeId,
    a.OwnerUserId,
    a.Title,
    a.Tags,
    a.CreationDate,
    a.Score,
    a.ViewCount,
    a.CommentCount,
    a.AnswerCount,
    a.FavoriteCount,
    a.LastActivityDate,
    a.ContentLicense
  FROM Agg a
  WHERE a.rn_by_activity <= 10
),
UserStats AS (
  SELECT
    u.Id AS UserId,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    u.DisplayName,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.Location,
    u.ProfileImageUrl,
    u.AccountId,
    (SELECT COALESCE(SUM(v.BountyAmount),0) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 8) AS BountyGiven,
    (SELECT COUNT(*) FROM Posts pp WHERE pp.OwnerUserId = u.Id) AS PostCount
  FROM Users u
),
TopTagWikIs AS (
  SELECT
    t.Id AS TagId,
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId,
    CASE WHEN COALESCE(CASE WHEN t.IsModeratorOnly IS NULL THEN 0 WHEN t.IsModeratorOnly = TRUE THEN 1 ELSE 0 END, 0) <> 0 THEN TRUE ELSE FALSE END AS IsModeratorOnly,
    CASE WHEN COALESCE(CASE WHEN t.IsRequired IS NULL THEN 0 WHEN t.IsRequired = TRUE THEN 1 ELSE 0 END, 0) <> 0 THEN TRUE ELSE FALSE END AS IsRequired
  FROM Tags t
),
CrossLink AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    pl.LinkTypeId,
    lt.Name AS LinkTypeName
  FROM PostLinks pl
  JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  WHERE lt.Name IN ('Linked','Duplicate')
),
ActivityBreakdown AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.PostTypeId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpModCount,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownModCount,
    SUM(CASE WHEN v.VoteTypeId = 10 THEN 1 ELSE 0 END) AS DeletionVotes,
    COUNT(DISTINCT c.Id) AS CommentCount
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN Comments c ON c.PostId = p.Id
  GROUP BY p.Id, p.Title, p.PostTypeId
),
Compound AS (
  SELECT
    r.PostId,
    r.Title,
    r.PostTypeId,
    r.OwnerUserId,
    r.Tags,
    r.CreationDate,
    r.Score,
    r.ViewCount,
    r.CommentCount,
    r.AnswerCount,
    r.FavoriteCount,
    r.LastActivityDate,
    r.ContentLicense,
    a.UpModCount,
    a.DownModCount,
    a.DeletionVotes,
    a.CommentCount AS CommentCountFromAgg
  FROM RecentActivity r
  LEFT JOIN ActivityBreakdown a ON a.PostId = r.PostId
),
Final AS (
  SELECT
    c.PostId,
    c.Title,
    c.PostTypeId,
    u.DisplayName AS OwnerDisplayName,
    c.CreationDate,
    c.Score,
    c.ViewCount,
    c.CommentCount,
    c.AnswerCount,
    c.FavoriteCount,
    c.LastActivityDate,
    c.ContentLicense,
    tr.LinkTypeName,
    t.TagName,
    th.Name AS HistoryTypeName,
    ph.PostId AS ph_PostId,
    ph.PostHistoryTypeId AS ph_PostHistoryTypeId
  FROM Compound c
  LEFT JOIN Users u ON u.Id = c.OwnerUserId
  LEFT JOIN CrossLink tr ON tr.PostId = c.PostId
  LEFT JOIN Tags t ON t.ExcerptPostId = c.PostId OR t.WikiPostId = c.PostId
  LEFT JOIN PostHistory ph ON ph.PostId = c.PostId
  LEFT JOIN PostHistoryTypes th ON ph.PostHistoryTypeId = th.Id
  WHERE c.LastActivityDate IS NOT NULL
)
SELECT
  DISTINCT
  PostId,
  Title,
  PostTypeId,
  OwnerDisplayName,
  CreationDate,
  Score,
  ViewCount,
  CommentCount,
  AnswerCount,
  FavoriteCount,
  LastActivityDate,
  ContentLicense,
  COALESCE(LinkTypeName, 'NONE') AS LinkRelation,
  TagName,
  HistoryTypeName
FROM Final
ORDER BY LastActivityDate DESC
LIMIT 200;
WITH
RecentActivePosts AS (
  SELECT
    p.Id,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.PostTypeId,
    p.AcceptedAnswerId,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '90 days'
),
TopAuthors AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.Location,
    u.WebsiteUrl
  FROM Users u
  WHERE u.Reputation >= 10000
),
tagging AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.LastActivityDate,
    p.Tags,
    u.DisplayName AS OwnerDisplayName,
    pc.Name AS PostTypeName,
    pc.Id AS PostTypeId
  FROM Posts p
  LEFT JOIN PostTypes pc ON p.PostTypeId = pc.Id
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.LastActivityDate IS NOT NULL
),
LinkAnalytics AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    lt.Name AS LinkTypeName,
    p2.Title AS RelatedPostTitle
  FROM PostLinks pl
  LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  LEFT JOIN Posts p2 ON pl.RelatedPostId = p2.Id
  WHERE pl.PostId IN (SELECT Id FROM RecentActivePosts)
),
Commentary AS (
  SELECT
    c.PostId,
    AVG(COALESCE(c.Score, 0)) AS AvgCommentScore,
    COUNT(*) AS CommentCount
  FROM Comments c
  GROUP BY c.PostId
),
VotesAgg AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    SUM(CASE WHEN v.VoteTypeId = 6 THEN 1 ELSE 0 END) AS CloseVotes,
    SUM(CASE WHEN v.VoteTypeId = 10 THEN 1 ELSE 0 END) AS DeletionVotes
  FROM Votes v
  GROUP BY v.PostId
),
Indexed AS (
  SELECT
    rp.PostId,
    rp.RelatedPostId,
    rp.LinkTypeName,
    rp.RelatedPostTitle,
    COALESCE(va.UpVotes, 0) AS UpVotes,
    COALESCE(va.DownVotes, 0) AS DownVotes,
    COALESCE(va.CloseVotes, 0) AS CloseVotes,
    COALESCE(va.DeletionVotes, 0) AS DeletionVotes,
    COALESCE(c.AvgCommentScore, 0) AS AvgCommentScore,
    COALESCE(c.CommentCount, 0) AS CommentCount
  FROM LinkAnalytics rp
  LEFT JOIN VotesAgg va ON rp.PostId = va.PostId
  LEFT JOIN Commentary c ON rp.PostId = c.PostId
)
SELECT
  t.Id AS PostId,
  t.Title AS PostTitle,
  iu.DisplayName AS OwnerDisplayName,
  t.LastActivityDate,
  t.Tags,
  pt.Name AS PostTypeName,
  t.PostTypeId,
  t.AcceptedAnswerId,
  t.ViewCount,
  t.Score,
  t.OwnerUserId,
  la.DisplayName AS LastEditorDisplayName,
  la.Reputation AS LastEditorReputation,
  (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = t.Id) AS LinkCount,
  COALESCE(i.UpVotes, 0) AS UpVotes,
  COALESCE(i.DownVotes, 0) AS DownVotes,
  COALESCE(i.CloseVotes, 0) AS CloseVotes,
  COALESCE(i.DeletionVotes, 0) AS DeletionVotes,
  COALESCE(i.AvgCommentScore, 0) AS AvgCommentScore,
  COALESCE(i.CommentCount, 0) AS CommentCount
FROM RecentActivePosts t
LEFT JOIN TopAuthors iu ON t.OwnerUserId = iu.UserId
LEFT JOIN Indexed i ON t.Id = i.PostId
LEFT JOIN Posts p ON p.Id = t.Id
LEFT JOIN PostTypes pt ON pt.Id = t.PostTypeId
LEFT JOIN Users la ON la.Id = p.LastEditorUserId
WHERE t.rn = 1
GROUP BY
  t.Id,
  t.Title,
  iu.DisplayName,
  t.LastActivityDate,
  t.Tags,
  pt.Name,
  t.PostTypeId,
  t.AcceptedAnswerId,
  t.ViewCount,
  t.Score,
  t.OwnerUserId,
  la.DisplayName,
  la.Reputation,
  i.UpVotes,
  i.DownVotes,
  i.CloseVotes,
  i.DeletionVotes,
  i.AvgCommentScore,
  i.CommentCount
ORDER BY t.LastActivityDate DESC, t.Score DESC
LIMIT 100;
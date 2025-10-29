-- {"query": "5392.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 913} 
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
  WHERE p.CreationDate >= NOW() - INTERVAL '90 days'
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
    AVG(COALESCE(c.Score,0)) AS AvgCommentScore,
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
    va.UpVotes,
    va.DownVotes,
    va.CloseVotes,
    va.DeletionVotes,
    c.AvgCommentScore,
    c.CommentCount
  FROM LinkAnalytics rp
  LEFT JOIN VotesAgg va ON rp.PostId = va.PostId
  LEFT JOIN Commentary c ON rp.PostId = c.PostId
)
SELECT
  t.PostId,
  t.Title AS PostTitle,
  t.OwnerDisplayName,
  t.LastActivityDate,
  t.Tags,
  t.PostTypeName,
  t.PostTypeId,
  t.AcceptedAnswerId,
  t.ViewCount,
  t.Score,
  t.OwnerUserId,
  iu.DisplayName AS LastEditorDisplayName,
  iu.Reputation AS LastEditorReputation,
  (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = t.PostId) AS LinkCount,
  COALESCE(i.UpVotes, 0) AS UpVotes,
  COALESCE(i.DownVotes, 0) AS DownVotes,
  COALESCE(i.CloseVotes, 0) AS CloseVotes,
  COALESCE(i.DeletionVotes, 0) AS DeletionVotes,
  COALESCE(i.AvgCommentScore, 0) AS AvgCommentScore,
  COALESCE(i.CommentCount, 0) AS CommentCount
FROM RecentActivePosts t
LEFT JOIN TopAuthors iu ON t.OwnerUserId = iu.UserId
LEFT JOIN Indexed i ON t.Id = i.PostId
WHERE t.rn = 1
ORDER BY t.LastActivityDate DESC, t.Score DESC
LIMIT 100;
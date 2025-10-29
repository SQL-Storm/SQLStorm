-- {"query": "5557.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 869}
WITH TopPosts AS (
  SELECT
    p.Id,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    p.PostTypeId,
    p.LastActivityDate,
    p.FavoriteCount,
    p.ContentLicense,
    u.DisplayName AS OwnerName,
    u.Reputation,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId IN (1, 2)
), 
RecentActivity AS (
  SELECT
    t.Id,
    t.Name AS TypeName,
    tx.PostId,
    tx.RevisionGUID,
    tx.CreationDate AS RevisionDate,
    tx.UserDisplayName,
    tx.Comment,
    tx.Text,
    tx.PostHistoryTypeId
  FROM PostHistory tx
  JOIN PostHistoryTypes t ON tx.PostHistoryTypeId = t.Id
  WHERE tx.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30 days')
),
TagMetrics AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId,
    (SELECT MAX(p.LastActivityDate)
     FROM Posts p
     WHERE p.Id = t.WikiPostId OR p.Id = t.ExcerptPostId) AS LastTagUpdate
  FROM Tags t
  WHERE COALESCE(t.IsModeratorOnly, FALSE) = FALSE
),
CrossLinkStats AS (
  SELECT
    pl.PostId,
    COUNT(CASE WHEN LOWER(lt.Name) LIKE '%duplicate%' THEN 1 END) AS DuplicateLinks,
    COUNT(*) AS TotalLinks
  FROM PostLinks pl
  JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  GROUP BY pl.PostId
),
BadgeActivity AS (
  SELECT
    b.UserId,
    COUNT(*) AS BadgeCount,
    MAX(b.Date) AS LastBadgeDate
  FROM Badges b
  GROUP BY b.UserId
),
AggVotes AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    SUM(CASE WHEN v.VoteTypeId = 6 THEN 1 ELSE 0 END) AS CloseVotes
  FROM Votes v
  GROUP BY v.PostId
),
PostTypes AS (
  SELECT 1 AS Id, 'Question' AS Name
  UNION ALL
  SELECT 2 AS Id, 'Answer' AS Name
)
SELECT
  tp.Id AS PostId,
  tp.Title,
  pt.Name AS PostType,
  tp.CreationDate AS PostCreation,
  tp.Score,
  tp.ViewCount,
  tp.OwnerName,
  tp.Reputation,
  tp.Tags,
  tp.AnswerCount,
  tp.CommentCount,
  tp.LastActivityDate,
  tp.FavoriteCount,
  tp.ContentLicense,
  ra.RevisionDate,
  ra.UserDisplayName AS RevisionUser,
  ra.Comment AS RevisionComment,
  tm.LastTagUpdate,
  cm.TotalLinks,
  cm.DuplicateLinks,
  ba.BadgeCount,
  ba.LastBadgeDate,
  av.UpVotes,
  av.DownVotes,
  av.CloseVotes,
  pt.Name AS TagOrTopic
FROM TopPosts tp
LEFT JOIN RecentActivity ra ON ra.PostId = tp.Id
LEFT JOIN TagMetrics tm ON tm.ExcerptPostId = tp.Id OR tm.WikiPostId = tp.Id
LEFT JOIN CrossLinkStats cm ON cm.PostId = tp.Id
LEFT JOIN BadgeActivity ba ON ba.UserId = tp.OwnerUserId
LEFT JOIN AggVotes av ON av.PostId = tp.Id
LEFT JOIN PostTypes pt ON tp.PostTypeId = pt.Id
WHERE tp.rn = 1
GROUP BY
  tp.Id,
  tp.Title,
  pt.Name,
  tp.CreationDate,
  tp.Score,
  tp.ViewCount,
  tp.OwnerName,
  tp.Reputation,
  tp.Tags,
  tp.AnswerCount,
  tp.CommentCount,
  tp.LastActivityDate,
  tp.FavoriteCount,
  tp.ContentLicense,
  ra.RevisionDate,
  ra.UserDisplayName,
  ra.Comment,
  tm.LastTagUpdate,
  cm.TotalLinks,
  cm.DuplicateLinks,
  ba.BadgeCount,
  ba.LastBadgeDate,
  av.UpVotes,
  av.DownVotes,
  av.CloseVotes,
  tp.rn
ORDER BY tp.Score DESC, tp.ViewCount DESC
LIMIT 100;
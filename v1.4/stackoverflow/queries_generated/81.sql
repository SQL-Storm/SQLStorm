-- {"query": "81.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1010} 
WITH
RecentActivePosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.ParentId,
    p.AcceptedAnswerId,
    p.CommentCount,
    p.FavoriteCount
  FROM Posts p
  WHERE p.LastActivityDate >= CURRENT_DATE - INTERVAL '30 days'
),
TopTags AS (
  SELECT
    t.TagName,
    COUNT(*) AS PostCount
  FROM Tags tg
  JOIN Posts p ON p.Id = tg.Id
  WHERE p.PostTypeId = 1
    AND tg.TagName IS NOT NULL
  GROUP BY t.TagName
),
UserStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id) AS BadgeCount,
    (SELECT COUNT(*) FROM Posts pr WHERE pr.OwnerUserId = u.Id AND pr.PostTypeId = 1) AS QuestionCount,
    (SELECT COUNT(*) FROM Posts pr WHERE pr.OwnerUserId = u.Id AND pr.PostTypeId = 2) AS AnswerCount
  FROM Users u
  WHERE u.Reputation > 100
),
AdvancedMetrics AS (
  SELECT
    p.PostId,
    p.PostTypeId,
    p.ParentId,
    p.OwnerUserId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.CommentCount,
    p.FavoriteCount,
    (SELECT SUM(v.BountyAmount) FROM Votes v WHERE v.PostId = p.PostId AND v.VoteTypeId = 8) AS TotalBounty,
    (SELECT COUNT(*) FROM Votes w WHERE w.PostId = p.PostId AND w.VoteTypeId IN (2,7)) AS UpOrReopenVotes,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS RnkByScore
  FROM RecentActivePosts p
),
JoinedPostLinks AS (
  SELECT
    a.PostId,
    a.RelatedPostId,
    lt.Name AS LinkTypeName,
    a.CreationDate
  FROM PostLinks a
  JOIN LinkTypes lt ON lt.Id = a.LinkTypeId
  WHERE a.PostId IN (SELECT PostId FROM RecentActivePosts)
),
CorrelatedHistory AS (
  SELECT
    ph.PostId,
    ph.PostHistoryTypeId,
    ph.Text,
    ph.CreationDate,
    ph.UserId,
    ph.UserDisplayName,
    ph.Comment
  FROM PostHistory ph
  WHERE ph.CreationDate >= CURRENT_DATE - INTERVAL '60 days'
    AND ph.PostId IN (SELECT PostId FROM RecentActivePosts)
)
SELECT
  u.UserId AS UserId,
  u.DisplayName AS UserDisplayName,
  u.Reputation,
  u.CreateDate AS CreationDate,
  u.LastAccessDate,
  u.Views,
  u.UpVotes,
  u.DownVotes,
  u.BadgeCount,
  u.QuestionCount,
  u.AnswerCount,
  p.PostId,
  p.PostTypeId,
  p.ParentId,
  p.Title,
  p.CreationDate AS PostCreationDate,
  p.LastActivityDate,
  p.Score,
  p.ViewCount,
  p.Tags,
  p.CommentCount,
  p.FavoriteCount,
  p.TotalBounty,
  p.UpOrReopenVotes,
  p.RnkByScore,
  t.TagName,
  lkn.RelatedPostId AS LinkedPostId,
  lkn.Name AS LinkTypeName,
  ch.PostId AS HistoryPostId,
  ch.PostHistoryTypeId,
  ch.Text AS HistoryText,
  ch.CreationDate AS HistoryDate,
  ch.UserDisplayName AS HistoryUser
FROM AdvancedMetrics p
LEFT JOIN UserStats u ON p.OwnerUserId = u.UserId
LEFT JOIN (
  SELECT
    b.UserId,
    b.Name AS TagName,
    b.Date
  FROM Badges b
  WHERE b.TagBased = 1
) t ON t.TagName = ANY(string_to_array(p.Tags, ','))
LEFT JOIN (
  SELECT a.PostId, a.RelatedPostId, a.LinkTypeName
  FROM JoinedPostLinks a
) lkn ON lkn.PostId = p.PostId
LEFT JOIN CorrelatedHistory ch ON ch.PostId = p.PostId
ORDER BY p.LastActivityDate DESC
LIMIT 100;
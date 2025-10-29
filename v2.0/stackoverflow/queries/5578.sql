WITH
ActiveUsers AS (
  SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl,
    u.AccountId,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.LastAccessDate DESC) AS rn
  FROM Users u
),
TopTags AS (
  SELECT
    t.TagName,
    t.Count,
    ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS rn
  FROM Tags t
  WHERE t.IsModeratorOnly = FALSE
),
Q AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.OwnerDisplayName,
    p.AcceptedAnswerId,
    p.ParentId,
    p.CommentCount,
    p.FavoriteCount,
    p.ContentLicense,
    pg.CloseReason AS CloseReason
  FROM Posts p
  LEFT JOIN (
    SELECT
      ph.PostId,
      ph.Comment AS CloseReason
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10
  ) pg ON pg.PostId = p.Id
  WHERE p.PostTypeId IN (1,2)
),
CorrelatedStats AS (
  SELECT
    q.PostId,
    q.PostTypeId,
    q.Title,
    q.Tags,
    q.CreationDate,
    q.LastActivityDate,
    q.Score,
    q.ViewCount,
    q.OwnerUserId,
    q.OwnerDisplayName,
    q.AcceptedAnswerId,
    q.ParentId,
    q.CommentCount,
    q.FavoriteCount,
    q.ContentLicense,
    q.CloseReason,
    u.Reputation AS OwnerReputation,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = q.PostId) AS CommentCountForPost,
    (SELECT STRING_AGG(ct.Name, ',') FROM Votes v
       JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
       JOIN PostHistory ph ON ph.PostId = q.PostId AND ph.PostHistoryTypeId = 52
       LEFT JOIN Posts p2 ON p2.Id = ph.PostId
       LEFT JOIN PostHistoryTypes ct ON ph.PostHistoryTypeId = ct.Id
       WHERE v.PostId = q.PostId AND v.VoteTypeId = 2) AS UpvoteTrail
  FROM Q q
  LEFT JOIN Users u ON q.OwnerUserId = u.Id
),
Windowed AS (
  SELECT
    cs.PostId,
    cs.PostTypeId,
    cs.Title,
    cs.Tags,
    cs.CreationDate,
    cs.LastActivityDate,
    cs.Score,
    cs.ViewCount,
    cs.OwnerUserId,
    cs.OwnerDisplayName,
    cs.AcceptedAnswerId,
    cs.ParentId,
    cs.CommentCount,
    cs.FavoriteCount,
    cs.ContentLicense,
    cs.CloseReason,
    cs.OwnerReputation,
    cs.CommentCountForPost,
    cs.UpvoteTrail,
    ROW_NUMBER() OVER (PARTITION BY cs.PostTypeId ORDER BY cs.Score DESC, cs.CreationDate DESC) AS wpos
  FROM CorrelatedStats cs
),
Final AS (
  SELECT
    w.PostId,
    w.PostTypeId,
    w.Title,
    w.Tags,
    w.CreationDate,
    w.LastActivityDate,
    w.Score,
    w.ViewCount,
    w.OwnerUserId,
    w.OwnerDisplayName,
    w.AcceptedAnswerId,
    w.ParentId,
    w.CommentCount,
    w.FavoriteCount,
    w.ContentLicense,
    w.CloseReason,
    w.OwnerReputation,
    w.CommentCountForPost,
    w.UpvoteTrail,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = w.OwnerUserId AND p2.CreationDate > w.CreationDate) AS PostsAfter,
    w.wpos
  FROM Windowed w
  WHERE w.wpos <= 100
)
SELECT
  f.PostId,
  f.Title,
  f.Tags,
  f.PostTypeId,
  f.CreationDate,
  f.LastActivityDate,
  f.Score,
  f.ViewCount,
  f.OwnerDisplayName,
  f.OwnerReputation,
  f.CommentCount AS CommentCountOnPost,
  f.CloseReason,
  f.PostsAfter,
  (SELECT STRING_AGG(t.TagName, ',') FROM Tags t WHERE POSITION(',' || t.TagName || ',' IN ',' || f.Tags || ',') > 0) AS DetectedTags,
  (CASE WHEN f.PostTypeId = 1 THEN 'Question' ELSE 'Answer' END) AS PostKind
FROM Final f
ORDER BY f.CreationDate DESC, f.Score DESC
LIMIT 300;
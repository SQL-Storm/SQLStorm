-- {"query": "5578.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 755} 
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
  WHERE t.IsModeratorOnly = 0
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
  WHERE p.PostTypeId IN (1,2) -- Questions and Answers
),
CorrelatedStats AS (
  SELECT
    q.*,
    u.Reputation AS OwnerReputation,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = q.PostId) AS CommentCountForPost,
    (SELECT STRING_AGG(ct.Name, ',') FROM Votes v JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
       JOIN PostHistory ph ON ph.PostId = q.PostId AND ph.PostHistoryTypeId = 52
       LEFT JOIN Posts p2 ON p2.Id = ph.PostId
       LEFT JOIN PostHistoryTypes ct ON ph.PostHistoryTypeId = ct.Id
       WHERE v.PostId = q.PostId AND v.VoteTypeId = 2) AS UpvoteTrail
  FROM Q
  LEFT JOIN Users u ON q.OwnerUserId = u.Id
),
Windowed AS (
  SELECT
    cs.*,
    ROW_NUMBER() OVER (PARTITION BY cs.PostTypeId ORDER BY cs.Score DESC, cs.CreationDate DESC) AS wpos
  FROM CorrelatedStats cs
),
Final AS (
  SELECT
    w.*,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = w.OwnerUserId AND p2.CreationDate > w.CreationDate) AS PostsAfter
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
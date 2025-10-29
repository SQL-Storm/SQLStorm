WITH TopPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.OwnerDisplayName,
    p.LastActivityDate,
    p.LastEditDate,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.PostTypeId,
    COALESCE(p.AcceptedAnswerId, -1) AS AcceptedAnswerId
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
),
RecentActivity AS (
  SELECT
    t.PostId,
    t.RevisionGUID,
    t.CreationDate AS RevisionDate,
    t.UserId AS RevisionUserId,
    t.UserDisplayName,
    t.Comment,
    t.Text
  FROM PostHistory t
  JOIN PostHistoryTypes ttypes ON t.PostHistoryTypeId = ttypes.Id
  WHERE ttypes.Name LIKE 'Edit %' OR ttypes.Name LIKE 'Post Closed' OR ttypes.Name LIKE 'Post Reopened'
),
TagStats AS (
  SELECT
    t.TagName,
    t.Count AS TagCount,
    m.Id AS MasterPostId
  FROM Tags t
  JOIN Posts m ON t.ExcerptPostId = m.Id
  WHERE t.IsModeratorOnly = FALSE
),
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    u.Location,
    u.WebsiteUrl,
    u.AboutMe,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id) AS PostsCount,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id) AS CommentsCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id) AS VotesCast
  FROM Users u
  WHERE u.Reputation > 100
),
CrossJoinSample AS (
  SELECT
    p.PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.OwnerDisplayName,
    p.LastActivityDate,
    p.LastEditDate,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.PostTypeId,
    p.AcceptedAnswerId,
    r.RevisionDate,
    r.RevisionUserId,
    r.Comment AS RevisionComment,
    r.Text AS RevisionText,
    ts.TagName
  FROM TopPosts p
  LEFT JOIN RecentActivity r ON r.PostId = p.PostId
  LEFT JOIN TagStats ts ON ts.MasterPostId = p.PostId
  -- CROSS JOIN LATERAL with a no-op is not standard across all dialects; emulate with a simple SELECT when supported.
  -- If your SQL dialect supports LATERAL and pg_sleep, you can re-enable; here we omit the lateral no-op.
  -- CROSS JOIN (SELECT 1) AS dummy
  -- keep as-is but using a simple cross join to a one-row derived table for portability:
  CROSS JOIN (SELECT 1 AS dummy_col) AS dummy
)
SELECT
  c.PostId,
  c.Title,
  c.Tags,
  c.CreationDate,
  c.Score,
  c.ViewCount,
  c.OwnerUserId,
  c.OwnerDisplayName,
  c.LastActivityDate,
  c.LastEditDate,
  c.AnswerCount,
  c.CommentCount,
  c.FavoriteCount,
  c.PostTypeId,
  c.AcceptedAnswerId,
  c.RevisionDate,
  c.RevisionUserId,
  c.RevisionComment,
  c.RevisionText,
  c.TagName,
  ua.UserId,
  ua.DisplayName AS OwnerDisplayNameFromUsers,
  ua.Reputation,
  ua.CreationDate AS UserCreationDate,
  ua.LastAccessDate,
  ua.Views AS UserViews,
  ua.UpVotes AS UserUpVotes,
  ua.DownVotes AS UserDownVotes,
  ua.AccountId,
  ua.Location,
  ua.WebsiteUrl,
  ua.AboutMe,
  ua.PostsCount,
  ua.CommentsCount,
  ua.VotesCast
FROM CrossJoinSample c
LEFT JOIN UserActivity ua ON ua.UserId = c.OwnerUserId
WHERE
  (c.ViewCount > 1000 OR c.Score > 50)
  AND (c.CreationDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '180' DAY))
  AND (c.TagName IS NULL OR c.TagName <> '')
GROUP BY
  c.PostId,
  c.Title,
  c.Tags,
  c.CreationDate,
  c.Score,
  c.ViewCount,
  c.OwnerUserId,
  c.OwnerDisplayName,
  c.LastActivityDate,
  c.LastEditDate,
  c.AnswerCount,
  c.CommentCount,
  c.FavoriteCount,
  c.PostTypeId,
  c.AcceptedAnswerId,
  c.RevisionDate,
  c.RevisionUserId,
  c.RevisionComment,
  c.RevisionText,
  c.TagName,
  ua.UserId,
  ua.DisplayName,
  ua.Reputation,
  ua.CreationDate,
  ua.LastAccessDate,
  ua.Views,
  ua.UpVotes,
  ua.DownVotes,
  ua.AccountId,
  ua.Location,
  ua.WebsiteUrl,
  ua.AboutMe,
  ua.PostsCount,
  ua.CommentsCount,
  ua.VotesCast
ORDER BY c.Score DESC, c.ViewCount DESC
LIMIT 100;
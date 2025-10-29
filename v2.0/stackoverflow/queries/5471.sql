WITH top_users AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.UpVotes DESC) AS rn
  FROM Users u
  WHERE u.Reputation > 1000
),
recent_activity AS (
  SELECT
    p.OwnerUserId,
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.Tags,
    p.LastActivityDate,
    (SELECT MAX(v.CreationDate) FROM Votes v WHERE v.PostId = p.Id) AS LastVoteDate,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount
  FROM Posts p
  WHERE p.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '180 days')
),
ownership_posts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.ViewCount,
    p.Score,
    p.Tags,
    (SELECT MAX(v.CreationDate) FROM Votes v WHERE v.PostId = p.Id) AS LastVoteDate,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount
  FROM Posts p
),
ownership AS (
  SELECT
    tu.UserId,
    CAST(NULL AS INTEGER) AS CommunityOwnerUserId,
    op.PostId,
    op.Title AS PostTitle,
    op.CreationDate AS PostCreationDate,
    op.LastActivityDate AS PostLastActivityDate,
    op.ViewCount,
    op.Score,
    op.CommentCount,
    op.LastVoteDate,
    op.Tags
  FROM top_users tu
  LEFT JOIN ownership_posts op ON op.PostId = op.PostId
)
SELECT
  tu.UserId,
  tu.DisplayName,
  tu.Reputation,
  tu.CreationDate AS UserCreationDate,
  tu.LastAccessDate,
  tu.Location,
  tu.Views,
  tu.UpVotes,
  tu.DownVotes,
  tu.AccountId,
  ro.PostId,
  ro.PostTitle,
  ro.PostCreationDate,
  ro.PostLastActivityDate,
  ro.ViewCount,
  ro.Score,
  ro.CommentCount,
  ro.LastVoteDate,
  ro.Tags
FROM top_users tu
LEFT JOIN (
  SELECT
    w.OwnerUserId AS UserId,
    w.PostId,
    w.Title AS PostTitle,
    w.CreationDate AS PostCreationDate,
    w.LastActivityDate AS PostLastActivityDate,
    w.ViewCount,
    w.Score,
    w.CommentCount,
    w.LastVoteDate,
    w.Tags
  FROM recent_activity w
) ro ON ro.UserId = tu.UserId
WHERE ro.PostId IS NOT NULL
GROUP BY
  tu.UserId,
  tu.DisplayName,
  tu.Reputation,
  tu.CreationDate,
  tu.LastAccessDate,
  tu.Location,
  tu.Views,
  tu.UpVotes,
  tu.DownVotes,
  tu.AccountId,
  ro.PostId,
  ro.PostTitle,
  ro.PostCreationDate,
  ro.PostLastActivityDate,
  ro.ViewCount,
  ro.Score,
  ro.CommentCount,
  ro.LastVoteDate,
  ro.Tags
ORDER BY tu.Reputation DESC, ro.LastVoteDate DESC
LIMIT 100;
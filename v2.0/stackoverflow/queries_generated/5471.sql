-- {"query": "5471.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 637} 
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
    -- correlate: most recent vote date on the post
    (SELECT MAX(v.CreationDate)
     FROM Votes v
     WHERE v.PostId = p.Id) AS LastVoteDate,
    -- count comments on the post
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount
  FROM Posts p
  WHERE p.CreationDate >= NOW() - INTERVAL '180 days'
),
ownership AS (
  SELECT
    ru.UserId,
    cu.UserId AS CommunityOwnerUserId,
    ro.PostId,
    ro.Title AS PostTitle,
    ro.CreationDate AS PostCreationDate,
    ro.LastActivityDate AS PostLastActivityDate,
    ro.ViewCount,
    ro.Score,
    ro.CommentCount,
    ro.LastVoteDate,
    ro.Tags
  FROM top_users tu
  LEFT JOIN Posts ro ON ro.OwnerUserId = tu.UserId
  LEFT JOIN (
    SELECT
      p.Id AS PostId,
      p.Title,
      p.CreationDate,
      p.LastActivityDate,
      p.ViewCount,
      p.Score,
      p.Tags,
      p.LastActivityDate AS LastVoteDate,
      p.CommentCount
    FROM Recent
  ) ro ON ro.PostId = ro.PostId
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
    w.UserId,
    w.PostId,
    w.PostTitle,
    w.PostCreationDate,
    w.PostLastActivityDate,
    w.ViewCount,
    w.Score,
    w.CommentCount,
    w.LastVoteDate,
    w.Tags
  FROM recent_activity w
) ro ON ro.UserId = tu.UserId
WHERE ro.PostId IS NOT NULL
ORDER BY tu.Reputation DESC, ro.LastVoteDate DESC
LIMIT 100;
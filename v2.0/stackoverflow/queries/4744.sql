WITH
  PostEngagement AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.Title,
      p.PostTypeId,
      p.CreationDate AS PostCreationDate,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ViewCount,
      (SELECT COUNT(*) FROM Votes v1 WHERE v1.PostId = p.Id AND v1.VoteTypeId = 2) AS UpVoteCount,
      (SELECT COUNT(*) FROM Votes v2 WHERE v2.PostId = p.Id AND v2.VoteTypeId = 3) AS DownVoteCount,
      COALESCE(
        (
          SELECT
            COUNT(*)
          FROM
            Comments c
          WHERE
            c.PostId = p.Id
        ),
        0
      ) AS CommentCountSubquery,
      ROW_NUMBER() OVER (
        PARTITION BY
          p.OwnerUserId
        ORDER BY
          p.CreationDate DESC
      ) AS PostSequenceForUser
    FROM
      Posts p
    WHERE
      p.PostTypeId IN (1, 2)
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      u.LastAccessDate,
      u.Views AS UserViews,
      u.UpVotes AS UserUpVotes,
      u.DownVotes AS UserDownVotes,
      (
        SELECT
          COUNT(*)
        FROM
          Badges b
        WHERE
          b.UserId = u.Id
      ) AS BadgeCount,
      COALESCE(
        (
          SELECT
            COUNT(DISTINCT ph.PostId)
          FROM
            PostHistory ph
          WHERE
            ph.UserId = u.Id
            AND ph.PostHistoryTypeId IN (2, 5)
        ),
        0
      ) AS EditedPostCount
    FROM
      Users u
    WHERE
      u.AccountId IS NOT NULL
  ),
  PostMetaData AS (
    SELECT
      pe.PostId,
      pe.OwnerUserId,
      pe.Title,
      pe.PostCreationDate,
      pe.AnswerCount,
      pe.CommentCount,
      pe.FavoriteCount,
      pe.ViewCount,
      pe.UpVoteCount,
      pe.DownVoteCount,
      pe.CommentCountSubquery,
      CASE
        WHEN pe.PostTypeId = 1 THEN 'Question'
        WHEN pe.PostTypeId = 2 THEN 'Answer'
        ELSE 'Other'
      END AS PostTypeDescription,
      CASE
        WHEN pe.ViewCount > 10000 THEN 'High Traffic'
        WHEN pe.ViewCount > 1000 THEN 'Medium Traffic'
        ELSE 'Low Traffic'
      END AS TrafficCategory,
      CASE
        WHEN pe.AnswerCount > 5 THEN 'Many Answers'
        WHEN pe.AnswerCount > 0 THEN 'Some Answers'
        ELSE 'No Answers'
      END AS AnswerCountCategory,
      CONCAT(
        pe.UpVoteCount,
        '/',
        pe.DownVoteCount
      ) AS VoteRatio,
      pe.PostSequenceForUser
    FROM
      PostEngagement pe
  )
SELECT
  pm.PostId,
  pm.Title,
  ua.DisplayName AS OwnerDisplayName,
  ua.Reputation,
  ua.UserCreationDate,
  ua.LastAccessDate,
  pm.PostCreationDate,
  pm.PostTypeDescription,
  pm.TrafficCategory,
  pm.AnswerCountCategory,
  pm.UpVoteCount,
  pm.DownVoteCount,
  pm.VoteRatio,
  pm.CommentCount,
  pm.FavoriteCount,
  pm.ViewCount,
  ua.BadgeCount,
  ua.EditedPostCount,
  CASE
    WHEN ua.Reputation > 100000
      AND ua.BadgeCount >= 5
      AND pm.PostSequenceForUser <= 5 THEN 'Highly Engaged Veteran'
    WHEN ua.Reputation > 10000
      AND ua.EditedPostCount >= 10 THEN 'Active Contributor'
    WHEN ua.Reputation < 500 THEN 'New User'
    ELSE 'Standard User'
  END AS UserEngagementLevel,
  CASE
    WHEN pm.PostSequenceForUser = 1
      AND ua.UserCreationDate < cast('2024-10-01' as date) - INTERVAL '365' DAY THEN 'First Post - Established User'
    WHEN pm.PostSequenceForUser = 1 THEN 'First Post - New User'
    ELSE 'Subsequent Post'
  END AS PostSequenceDescription,
  COALESCE(ua.UserViews, 0) - COALESCE(ua.UserUpVotes, 0) AS NetUserVotes,
  ua.UserViews AS TotalUserViews,
  (ua.UserUpVotes + ua.UserDownVotes) AS TotalUserVoteActivity
FROM
  PostMetaData pm
LEFT OUTER JOIN
  UserActivity ua
ON
  pm.OwnerUserId = ua.UserId
WHERE
  pm.PostCreationDate >= (cast('2024-10-01' as date) - INTERVAL '1' YEAR)
  AND pm.ViewCount > 10
  AND pm.UpVoteCount + pm.DownVoteCount > 0
UNION
SELECT
  NULL AS PostId,
  'Summary Statistics' AS Title,
  NULL AS OwnerDisplayName,
  AVG(ua.Reputation) AS Reputation,
  MIN(ua.UserCreationDate) AS UserCreationDate,
  MAX(ua.LastAccessDate) AS LastAccessDate,
  NULL AS PostCreationDate,
  NULL AS PostTypeDescription,
  NULL AS TrafficCategory,
  NULL AS AnswerCountCategory,
  SUM(pm.UpVoteCount) AS UpVoteCount,
  SUM(pm.DownVoteCount) AS DownVoteCount,
  NULL AS VoteRatio,
  SUM(pm.CommentCount) AS CommentCount,
  SUM(pm.FavoriteCount) AS FavoriteCount,
  SUM(pm.ViewCount) AS ViewCount,
  AVG(ua.BadgeCount) AS BadgeCount,
  SUM(ua.EditedPostCount) AS EditedPostCount,
  NULL AS UserEngagementLevel,
  NULL AS PostSequenceDescription,
  NULL AS NetUserVotes,
  NULL AS TotalUserViews,
  NULL AS TotalUserVoteActivity
FROM
  PostMetaData pm
LEFT OUTER JOIN
  UserActivity ua
ON
  pm.OwnerUserId = ua.UserId
WHERE
  pm.PostCreationDate >= (cast('2024-10-01' as date) - INTERVAL '1' YEAR)
  AND pm.ViewCount > 10
  AND pm.UpVoteCount + pm.DownVoteCount > 0;
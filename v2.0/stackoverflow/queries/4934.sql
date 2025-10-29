WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.PostHistoryTypeId,
      ph.CreationDate,
      u.DisplayName AS EditorDisplayName,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    LEFT JOIN Users u
      ON ph.UserId = u.Id
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 7, 8)
  ),
  PostSummary AS (
    SELECT
      p.Id AS PostId,
      p.Title,
      p.PostTypeId,
      pt.Name AS PostTypeName,
      p.OwnerUserId,
      u.DisplayName AS OwnerDisplayName,
      p.CreationDate AS PostCreationDate,
      p.LastActivityDate,
      p.Score,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ClosedDate,
      CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        WHEN p.AnswerCount > 100 THEN 'Popular'
        ELSE 'Active'
      END AS PostStatus,
      COUNT(c.Id) AS CommentCount_
    FROM Posts p
    JOIN PostTypes pt
      ON p.PostTypeId = pt.Id
    LEFT JOIN Users u
      ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c
      ON p.Id = c.PostId
    WHERE
      p.PostTypeId IN (1, 2)
    GROUP BY
      p.Id,
      p.Title,
      p.PostTypeId,
      pt.Name,
      p.OwnerUserId,
      u.DisplayName,
      p.CreationDate,
      p.LastActivityDate,
      p.Score,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ClosedDate,
      p.CommunityOwnedDate
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotesReceived,
      COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotesReceived,
      COUNT(DISTINCT b.Id) AS NumberOfBadges,
      MAX(p.LastActivityDate) AS LastPostActivityDate
    FROM Users u
    LEFT JOIN Votes v
      ON u.Id = v.UserId
    LEFT JOIN Badges b
      ON u.Id = b.UserId
    LEFT JOIN Posts p
      ON u.Id = p.OwnerUserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation
  )
SELECT
  ps.PostId,
  ps.Title,
  ps.PostTypeName,
  ps.OwnerDisplayName,
  ps.PostCreationDate,
  ps.LastActivityDate,
  ps.Score,
  ps.AnswerCount,
  ps.CommentCount AS CommentCountFromPosts,
  ps.FavoriteCount,
  ps.PostStatus,
  rpe.EditorDisplayName,
  rpe.CreationDate AS LastEditDate,
  ua.Reputation AS OwnerReputation,
  ua.NumberOfBadges AS OwnerBadges,
  ua.UpVotesReceived AS OwnerUpVotesReceived,
  ua.DownVotesReceived AS OwnerDownVotesReceived,
  ua.LastPostActivityDate,
  (
    SELECT
      COUNT(*)
    FROM Comments c_inner
    WHERE
      c_inner.PostId = ps.PostId
      AND c_inner.UserId = ps.OwnerUserId
  ) AS OwnerCommentsOnOwnPost,
  CASE
    WHEN ps.ClosedDate IS NOT NULL THEN CAST('2024-10-01 12:34:56' AS timestamp) - ps.ClosedDate
    ELSE NULL
  END AS DaysSinceClosed,
  CHAR_LENGTH(ps.Title) AS TitleLength,
  SUBSTRING(ps.Title FROM 1 FOR 10) AS TitlePrefix,
  CASE
    WHEN ps.OwnerUserId IS NULL THEN 'Community'
    WHEN ps.OwnerDisplayName LIKE '%[deleted]%' THEN 'Deleted User'
    ELSE ua.DisplayName
  END AS FinalOwnerDisplayName
FROM PostSummary ps
LEFT JOIN RankedPostEdits rpe
  ON ps.PostId = rpe.PostId AND rpe.rn = 1
LEFT JOIN UserActivity ua
  ON ps.OwnerUserId = ua.UserId
WHERE
  ps.Score > 0
  AND ps.CommentCount_ > 0
  AND ps.PostTypeName IN ('Question', 'Answer')
  AND (
    ps.OwnerUserId IS NULL OR ua.Reputation > 1000 OR ua.NumberOfBadges >= 5
  )
UNION ALL
SELECT
  NULL AS PostId,
  NULL AS Title,
  NULL AS PostTypeName,
  NULL AS OwnerDisplayName,
  NULL AS PostCreationDate,
  NULL AS LastActivityDate,
  NULL AS Score,
  NULL AS AnswerCount,
  NULL AS CommentCountFromPosts,
  NULL AS FavoriteCount,
  NULL AS PostStatus,
  NULL AS EditorDisplayName,
  NULL AS LastEditDate,
  NULL AS OwnerReputation,
  NULL AS OwnerBadges,
  NULL AS OwnerUpVotesReceived,
  NULL AS OwnerDownVotesReceived,
  NULL AS LastPostActivityDate,
  NULL AS OwnerCommentsOnOwnPost,
  NULL AS DaysSinceClosed,
  NULL AS TitleLength,
  NULL AS TitlePrefix,
  NULL AS FinalOwnerDisplayName
FROM Users u
WHERE
  u.Id NOT IN (SELECT OwnerUserId FROM PostSummary WHERE OwnerUserId IS NOT NULL)
  AND u.Reputation > 5000;
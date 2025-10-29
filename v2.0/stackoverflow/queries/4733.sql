-- {"query": "4733.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1861}
WITH
  PostInteractions AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.PostTypeId,
      p.CreationDate AS PostCreationDate,
      p.Score AS PostScore,
      p.ViewCount AS PostViewCount,
      p.FavoriteCount AS PostFavoriteCount,
      p.AnswerCount AS PostAnswerCount,
      p.CommentCount AS PostCommentCount,
      p.ClosedDate,
      pt.Name AS PostTypeName,
      u.DisplayName AS OwnerDisplayName,
      COALESCE((
        SELECT SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END)
        FROM Votes v
        WHERE v.PostId = p.Id
      ), 0) AS UpVotes,
      COALESCE((
        SELECT SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)
        FROM Votes v
        WHERE v.PostId = p.Id
      ), 0) AS DownVotes,
      (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount_Subquery,
      (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id OR pl.RelatedPostId = p.Id) AS LinkCount,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PostNumberForUser
    FROM Posts p
    LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.OwnerUserId IS NOT NULL
      AND p.PostTypeId IN (1, 2)
  ),
  UserActivity AS (
    SELECT
      UserId,
      COUNT(Id) AS NumberOfVotes,
      SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
      SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes,
      SUM(CASE WHEN VoteTypeId = 8 THEN 1 ELSE 0 END) AS BountyStartVotes,
      COUNT(DISTINCT PostId) AS DistinctPostsVotedOn
    FROM Votes
    WHERE VoteTypeId IN (2, 3, 8)
    GROUP BY UserId
  ),
  HighReputationUsers AS (
    SELECT Id
    FROM Users
    WHERE Reputation > 50000
  ),
  RecentActivity AS (
    SELECT
      UserId,
      COUNT(Id) AS RecentActivityCount
    FROM PostHistory
    WHERE CreationDate > (DATE '2024-10-01' - INTERVAL '30 days')
    GROUP BY UserId
  )
SELECT
  pi.PostId,
  pi.PostTypeName,
  pi.OwnerDisplayName,
  pi.PostCreationDate,
  pi.PostScore,
  pi.PostViewCount,
  pi.PostFavoriteCount,
  pi.PostAnswerCount,
  pi.PostCommentCount,
  pi.UpVotes,
  pi.DownVotes,
  pi.CommentCount_Subquery,
  pi.LinkCount,
  pi.PostNumberForUser,
  COALESCE(ua.NumberOfVotes, 0) AS TotalUserVotes,
  COALESCE(ua.TotalUpVotes, 0) AS UserTotalUpVotes,
  COALESCE(ua.TotalDownVotes, 0) AS UserTotalDownVotes,
  COALESCE(ua.BountyStartVotes, 0) AS UserBountyStartVotes,
  COALESCE(ua.DistinctPostsVotedOn, 0) AS UserDistinctPostsVotedOn,
  CASE WHEN pi.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS PostStatus,
  CASE WHEN EXISTS (SELECT 1 FROM HighReputationUsers hru WHERE pi.OwnerUserId = hru.Id) THEN 'HighReputationOwner' ELSE 'RegularOwner' END AS OwnerReputationStatus,
  ra.RecentActivityCount,
  LOWER(SUBSTRING(pi.OwnerDisplayName FROM 1 FOR 3)) AS DisplayNamePrefix,
  (pi.PostScore * 1.5 + pi.PostViewCount * 0.1 - pi.PostCommentCount * 0.5) AS CalculatedMetric,
  COALESCE((
    SELECT COUNT(*) FROM PostHistory ph
    WHERE ph.PostId = pi.PostId
      AND ph.PostHistoryTypeId IN (4,5,6)
  ), 0) AS EditCount
FROM PostInteractions pi
LEFT JOIN UserActivity ua ON pi.OwnerUserId = ua.UserId
LEFT JOIN RecentActivity ra ON pi.OwnerUserId = ra.UserId
WHERE (
    pi.PostScore > 10
    AND pi.PostTypeId = 1
    AND pi.PostCreationDate > DATE '2023-01-01'
    AND (pi.PostTypeName LIKE '%Question%' OR pi.PostTypeName LIKE '%Answer%')
  )
  OR EXISTS (
    SELECT 1 FROM PostLinks pl2 WHERE pl2.PostId = pi.PostId AND pl2.LinkTypeId = 3
  )
UNION
SELECT
  pi.PostId,
  pi.PostTypeName,
  pi.OwnerDisplayName,
  pi.PostCreationDate,
  pi.PostScore,
  pi.PostViewCount,
  pi.PostFavoriteCount,
  pi.PostAnswerCount,
  pi.PostCommentCount,
  pi.UpVotes,
  pi.DownVotes,
  pi.CommentCount_Subquery,
  pi.LinkCount,
  pi.PostNumberForUser,
  COALESCE(ua.NumberOfVotes, 0) AS TotalUserVotes,
  COALESCE(ua.TotalUpVotes, 0) AS UserTotalUpVotes,
  COALESCE(ua.TotalDownVotes, 0) AS UserTotalDownVotes,
  COALESCE(ua.BountyStartVotes, 0) AS UserBountyStartVotes,
  COALESCE(ua.DistinctPostsVotedOn, 0) AS UserDistinctPostsVotedOn,
  CASE WHEN pi.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS PostStatus,
  CASE WHEN EXISTS (SELECT 1 FROM HighReputationUsers hru WHERE pi.OwnerUserId = hru.Id) THEN 'HighReputationOwner' ELSE 'RegularOwner' END AS OwnerReputationStatus,
  ra.RecentActivityCount,
  LOWER(SUBSTRING(pi.OwnerDisplayName FROM 1 FOR 3)) AS DisplayNamePrefix,
  (pi.PostScore * 1.5 + pi.PostViewCount * 0.1 - pi.PostCommentCount * 0.5) AS CalculatedMetric,
  COALESCE((
    SELECT COUNT(*) FROM PostHistory ph
    WHERE ph.PostId = pi.PostId
      AND ph.PostHistoryTypeId IN (4,5,6)
  ), 0) AS EditCount
FROM PostInteractions pi
LEFT JOIN UserActivity ua ON pi.OwnerUserId = ua.UserId
LEFT JOIN RecentActivity ra ON pi.OwnerUserId = ra.UserId
WHERE
  pi.PostScore < -5
  AND pi.PostTypeId = 2
ORDER BY
  CalculatedMetric DESC,
  PostCreationDate
LIMIT 1000;
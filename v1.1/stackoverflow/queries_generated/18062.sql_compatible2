WITH
  RankedUserVotes AS (
    SELECT
      v.UserId,
      v.PostId,
      v.VoteTypeId,
      v.CreationDate,
      ROW_NUMBER() OVER (PARTITION BY v.UserId ORDER BY v.CreationDate DESC) AS vote_rank
    FROM Votes v
    WHERE v.VoteTypeId IN (2, 3)
  ),
  UserPostInteractions AS (
    SELECT
      u.Id AS UserId,
      p.Id AS PostId,
      p.OwnerUserId,
      p.PostTypeId,
      p.CreationDate AS PostCreationDate,
      u.Reputation,
      u.Views AS UserViews,
      u.UpVotes AS UserUpVotes,
      u.DownVotes AS UserDownVotes,
      CASE WHEN pf.TagName IS NOT NULL THEN 1 ELSE 0 END AS IsFavoriteTag,
      CASE WHEN ph.PostHistoryTypeId = 1 THEN 1 ELSE 0 END AS IsInitialPost,
      CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END AS IsEditedPost,
      CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosedPost,
      CAST(DATE_PART('day', CAST(p.CreationDate AS timestamp) - CAST(u.CreationDate AS timestamp)) AS INTEGER) AS UserAgeAtPostCreation,
      RANK() OVER (PARTITION BY p.Id ORDER BY p.CreationDate ASC) AS PostRankByCreation,
      COUNT(c.Id) OVER (PARTITION BY p.Id) AS CommentCountForPost,
      AVG(CAST(c.Score AS DECIMAL(10, 2))) OVER (PARTITION BY p.Id) AS AvgCommentScoreForPost,
      SUM(CASE WHEN rv.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS TotalUpvotesForPost,
      SUM(CASE WHEN rv.VoteTypeId = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS TotalDownvotesForPost,
      COUNT(rv.UserId) OVER (PARTITION BY p.Id) AS DistinctVotersForPost,
      CASE
        WHEN POSITION('<sql>' IN p.Tags) > 0 OR POSITION('sql' IN p.Tags) > 0 THEN 'SQL'
        WHEN POSITION('<python>' IN p.Tags) > 0 OR POSITION('python' IN p.Tags) > 0 THEN 'Python'
        WHEN POSITION('<javascript>' IN p.Tags) > 0 OR POSITION('javascript' IN p.Tags) > 0 THEN 'JavaScript'
        WHEN POSITION('<java>' IN p.Tags) > 0 OR POSITION('java' IN p.Tags) > 0 THEN 'Java'
        ELSE 'Other'
      END AS PrimaryTagCategory
    FROM Posts p
    LEFT JOIN Users u
      ON p.OwnerUserId = u.Id
    LEFT JOIN PostHistory ph
      ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 1
    LEFT JOIN Tags pf
      ON (POSITION(pf.TagName IN p.Tags) > 0)
    LEFT JOIN Comments c
      ON p.Id = c.PostId
    LEFT JOIN RankedUserVotes rv
      ON p.Id = rv.PostId AND rv.vote_rank <= 5
    WHERE
      p.PostTypeId IN (1, 2)
      AND p.CreationDate >= TIMESTAMP '2023-01-01'
      AND p.Score > 0
      AND u.Reputation > 1000
  )
SELECT
  upi.UserId,
  upi.PostId,
  upi.PostCreationDate,
  upi.Reputation,
  upi.UserViews,
  upi.UserUpVotes,
  upi.UserDownVotes,
  upi.IsFavoriteTag,
  upi.IsInitialPost,
  upi.IsEditedPost,
  upi.IsClosedPost,
  upi.UserAgeAtPostCreation,
  upi.CommentCountForPost,
  upi.AvgCommentScoreForPost,
  upi.TotalUpvotesForPost,
  upi.TotalDownvotesForPost,
  upi.DistinctVotersForPost,
  upi.PrimaryTagCategory,
  SUM(upi.Reputation) OVER (PARTITION BY upi.PrimaryTagCategory ORDER BY upi.PostCreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeReputationByCategory,
  COUNT(upi.PostId) OVER (PARTITION BY upi.PrimaryTagCategory) AS PostCountForCategory,
  CASE
    WHEN upi.AvgCommentScoreForPost > 10 THEN 'High Engagement'
    WHEN upi.AvgCommentScoreForPost BETWEEN 5 AND 10 THEN 'Medium Engagement'
    ELSE 'Low Engagement'
  END AS CommentEngagementLevel,
  COALESCE(upi.UserAgeAtPostCreation, 0) AS UserAgeOrZero,
  LENGTH(CAST(upi.PostId AS VARCHAR)) AS PostIdLength,
  UPPER(SUBSTRING(upi.PrimaryTagCategory FROM 1 FOR 3)) AS TagCategoryPrefix
FROM UserPostInteractions upi
WHERE
  (upi.UserAgeAtPostCreation IS NULL OR upi.UserAgeAtPostCreation > 10)
  AND upi.PostRankByCreation <= 10
UNION ALL
SELECT
  CAST(NULL AS BIGINT) AS UserId,
  CAST(NULL AS BIGINT) AS PostId,
  CAST(NULL AS timestamp) AS PostCreationDate,
  CAST(NULL AS INTEGER) AS Reputation,
  CAST(NULL AS BIGINT) AS UserViews,
  CAST(NULL AS BIGINT) AS UserUpVotes,
  CAST(NULL AS BIGINT) AS UserDownVotes,
  CAST(NULL AS INTEGER) AS IsFavoriteTag,
  CAST(NULL AS INTEGER) AS IsInitialPost,
  CAST(NULL AS INTEGER) AS IsEditedPost,
  CAST(NULL AS INTEGER) AS IsClosedPost,
  CAST(NULL AS INTEGER) AS UserAgeAtPostCreation,
  CAST(NULL AS BIGINT) AS CommentCountForPost,
  CAST(NULL AS NUMERIC) AS AvgCommentScoreForPost,
  CAST(NULL AS BIGINT) AS TotalUpvotesForPost,
  CAST(NULL AS BIGINT) AS TotalDownvotesForPost,
  CAST(NULL AS BIGINT) AS DistinctVotersForPost,
  'Summary' AS PrimaryTagCategory,
  SUM(upi.Reputation) OVER (PARTITION BY upi.PrimaryTagCategory ORDER BY upi.PostCreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeReputationByCategory,
  COUNT(upi.PostId) OVER (PARTITION BY upi.PrimaryTagCategory) AS PostCountForCategory,
  CAST(NULL AS TEXT) AS CommentEngagementLevel,
  CAST(NULL AS INTEGER) AS UserAgeOrZero,
  CAST(NULL AS INTEGER) AS PostIdLength,
  CAST(NULL AS TEXT) AS TagCategoryPrefix
FROM UserPostInteractions upi;
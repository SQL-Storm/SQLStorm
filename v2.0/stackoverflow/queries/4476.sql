WITH
  PostEngagement AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.PostTypeId,
      p.CreationDate AS PostCreationDate,
      p.Score AS PostScore,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ClosedDate,
      pt.Name AS PostTypeName,
      (
        SELECT COUNT(c.Id)
        FROM Comments c
        WHERE c.PostId = p.Id
      ) AS CommentCountFromCommentsTable,
      (
        SELECT COUNT(ph.Id)
        FROM PostHistory ph
        WHERE ph.PostId = p.Id
          AND ph.PostHistoryTypeId IN (4, 5)
      ) AS EditCount,
      (
        SELECT COUNT(pv.Id)
        FROM Votes pv
        WHERE pv.PostId = p.Id
          AND pv.VoteTypeId IN (2, 3)
      ) AS VoteCount
    FROM Posts p
    JOIN PostTypes pt
      ON p.PostTypeId = pt.Id
    WHERE p.OwnerUserId IS NOT NULL
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      u.Views AS UserViews,
      u.UpVotes AS UserUpVotes,
      u.DownVotes AS UserDownVotes,
      (
        SELECT COUNT(b.Id)
        FROM Badges b
        WHERE b.UserId = u.Id
      ) AS BadgeCount,
      (
        SELECT COUNT(ph.Id)
        FROM PostHistory ph
        WHERE ph.UserId = u.Id
      ) AS PostHistoryCount,
      (
        SELECT COUNT(c.Id)
        FROM Comments c
        WHERE c.UserId = u.Id
      ) AS CommentCount,
      (
        SELECT COUNT(v.Id)
        FROM Votes v
        WHERE v.UserId = u.Id
      ) AS VoteCount
    FROM Users u
  ),
  PostLag AS (
    SELECT
      pe.PostId,
      pe.OwnerUserId,
      pe.PostTypeId,
      pe.PostTypeName,
      pe.PostCreationDate,
      pe.PostScore,
      pe.AnswerCount,
      pe.CommentCount,
      pe.FavoriteCount,
      pe.ClosedDate,
      pe.CommentCountFromCommentsTable,
      pe.EditCount,
      pe.VoteCount,
      LAG(pe.PostCreationDate, 1, pe.PostCreationDate) OVER (
        PARTITION BY pe.OwnerUserId
        ORDER BY pe.PostCreationDate
      ) AS PreviousPostCreationDate
    FROM PostEngagement pe
    WHERE pe.PostTypeId IN (1, 2)
  ),
  UserPostMetrics AS (
    SELECT
      pl.PostId,
      pl.OwnerUserId,
      pl.PostTypeName,
      pl.PostScore,
      pl.AnswerCount,
      pl.CommentCount,
      pl.FavoriteCount,
      pl.EditCount,
      pl.VoteCount,
      pl.ClosedDate,
      CASE WHEN pl.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
      EXTRACT(EPOCH FROM (pl.PostCreationDate - pl.PreviousPostCreationDate)) / 86400.0 AS TimeSincePreviousPost,
      ua.DisplayName AS OwnerDisplayName,
      ua.Reputation AS OwnerReputation,
      ua.UserCreationDate AS OwnerCreationDate,
      ua.BadgeCount AS OwnerBadgeCount,
      ua.PostHistoryCount AS OwnerPostHistoryCount,
      ua.CommentCount AS OwnerCommentCount,
      ua.VoteCount AS OwnerVoteCount,
      pl.CommentCountFromCommentsTable
    FROM PostLag pl
    LEFT JOIN UserActivity ua
      ON pl.OwnerUserId = ua.UserId
  ),
  Combined AS (
    SELECT
      upm.PostId,
      upm.OwnerUserId,
      upm.PostTypeName,
      upm.PostScore,
      upm.AnswerCount,
      upm.CommentCount,
      upm.FavoriteCount,
      upm.ClosedDate,
      upm.CommentCountFromCommentsTable,
      upm.EditCount,
      upm.VoteCount,
      upm.IsClosed,
      upm.TimeSincePreviousPost,
      upm.OwnerDisplayName,
      upm.OwnerReputation,
      upm.OwnerCreationDate,
      upm.OwnerBadgeCount,
      upm.OwnerPostHistoryCount,
      upm.OwnerCommentCount,
      upm.OwnerVoteCount,
      CASE
        WHEN upm.OwnerReputation > 10000 THEN 'High Reputation'
        WHEN upm.OwnerReputation BETWEEN 1000 AND 10000 THEN 'Medium Reputation'
        ELSE 'Low Reputation'
      END AS ReputationLevel,
      CASE
        WHEN upm.TimeSincePreviousPost < 1 THEN 'Rapid'
        WHEN upm.TimeSincePreviousPost BETWEEN 1 AND 7 THEN 'Regular'
        ELSE 'Infrequent'
      END AS PostingFrequency,
      (upm.PostTypeName || ' (' || CAST(upm.PostScore AS VARCHAR) || ') - ' || COALESCE(upm.OwnerDisplayName, 'Community')) AS PostSummary,
      upm.PostScore + upm.AnswerCount AS TotalEngagementScore,
      CASE
        WHEN upm.PostTypeName = 'Question' THEN upm.OwnerBadgeCount * 1.5
        WHEN upm.PostTypeName = 'Answer' THEN upm.OwnerBadgeCount * 1.2
        ELSE upm.OwnerBadgeCount
      END AS WeightedBadgeScore
    FROM UserPostMetrics upm
    WHERE
      upm.PostScore > 0
      OR upm.AnswerCount > 0
      OR upm.CommentCount > 0

    UNION ALL

    SELECT
      NULL AS PostId,
      NULL AS OwnerUserId,
      'All' AS PostTypeName,
      SUM(PostScore) AS PostScore,
      SUM(AnswerCount) AS AnswerCount,
      SUM(CommentCount) AS CommentCount,
      SUM(FavoriteCount) AS FavoriteCount,
      NULL AS ClosedDate,
      SUM(COALESCE(CommentCountFromCommentsTable,0)) AS CommentCountFromCommentsTable,
      SUM(COALESCE(EditCount,0)) AS EditCount,
      SUM(COALESCE(VoteCount,0)) AS VoteCount,
      CASE WHEN SUM(CASE WHEN IsClosed = 1 THEN 1 ELSE 0 END) > 0 THEN 1 ELSE 0 END AS IsClosed,
      AVG(TimeSincePreviousPost) AS TimeSincePreviousPost,
      NULL AS OwnerDisplayName,
      AVG(OwnerReputation) AS OwnerReputation,
      NULL AS OwnerCreationDate,
      AVG(OwnerBadgeCount) AS OwnerBadgeCount,
      AVG(OwnerPostHistoryCount) AS OwnerPostHistoryCount,
      AVG(OwnerCommentCount) AS OwnerCommentCount,
      AVG(OwnerVoteCount) AS OwnerVoteCount,
      NULL AS ReputationLevel,
      NULL AS PostingFrequency,
      'Overall Summary' AS PostSummary,
      SUM(PostScore + AnswerCount) AS TotalEngagementScore,
      AVG(
        CASE
          WHEN PostTypeName = 'Question' THEN OwnerBadgeCount * 1.5
          WHEN PostTypeName = 'Answer' THEN OwnerBadgeCount * 1.2
          ELSE OwnerBadgeCount
        END
      ) AS WeightedBadgeScore
    FROM UserPostMetrics
    GROUP BY GROUPING SETS ((PostTypeName), ())
  )
SELECT
  c.PostId,
  c.OwnerUserId,
  c.PostTypeName,
  c.PostScore,
  c.AnswerCount,
  c.CommentCount,
  c.FavoriteCount,
  c.ClosedDate,
  c.CommentCountFromCommentsTable,
  c.EditCount,
  c.VoteCount,
  c.IsClosed,
  c.TimeSincePreviousPost,
  c.OwnerDisplayName,
  c.OwnerReputation,
  c.OwnerCreationDate,
  c.OwnerBadgeCount,
  c.OwnerPostHistoryCount,
  c.OwnerCommentCount,
  c.OwnerVoteCount,
  c.ReputationLevel,
  c.PostingFrequency,
  c.PostSummary,
  c.TotalEngagementScore,
  c.WeightedBadgeScore
FROM Combined c
ORDER BY
  CASE WHEN c.PostTypeName = 'All' THEN 1 ELSE 0 END,
  c.PostScore DESC;
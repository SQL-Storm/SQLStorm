-- {"query": "4476.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1666} 

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
        SELECT
          COUNT(c.Id)
        FROM
          Comments c
        WHERE
          c.PostId = p.Id
      ) AS CommentCountFromCommentsTable,
      (
        SELECT
          COUNT(ph.Id)
        FROM
          PostHistory ph
        WHERE
          ph.PostId = p.Id
          AND ph.PostHistoryTypeId IN (4, 5)
      ) AS EditCount,
      (
        SELECT
          COUNT(pv.Id)
        FROM
          Votes pv
        WHERE
          pv.PostId = p.Id
          AND pv.VoteTypeId IN (2, 3)
      ) AS VoteCount
    FROM
      Posts p
      JOIN PostTypes pt
        ON p.PostTypeId = pt.Id
    WHERE
      p.OwnerUserId IS NOT NULL
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
        SELECT
          COUNT(b.Id)
        FROM
          Badges b
        WHERE
          b.UserId = u.Id
      ) AS BadgeCount,
      (
        SELECT
          COUNT(ph.Id)
        FROM
          PostHistory ph
        WHERE
          ph.UserId = u.Id
      ) AS PostHistoryCount,
      (
        SELECT
          COUNT(c.Id)
        FROM
          Comments c
        WHERE
          c.UserId = u.Id
      ) AS CommentCount,
      (
        SELECT
          COUNT(v.Id)
        FROM
          Votes v
        WHERE
          v.UserId = u.Id
      ) AS VoteCount
    FROM
      Users u
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
        PARTITION BY
          pe.OwnerUserId
        ORDER BY
          pe.PostCreationDate
      ) AS PreviousPostCreationDate
    FROM
      PostEngagement pe
    WHERE
      pe.PostTypeId IN (1, 2)
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
      CASE
        WHEN pl.ClosedDate IS NOT NULL THEN 1
        ELSE 0
      END AS IsClosed,
      (
        julianday(pl.PostCreationDate) - julianday(pl.PreviousPostCreationDate)
      ) AS TimeSincePreviousPost,
      ua.DisplayName AS OwnerDisplayName,
      ua.Reputation AS OwnerReputation,
      ua.UserCreationDate AS OwnerCreationDate,
      ua.BadgeCount AS OwnerBadgeCount,
      ua.PostHistoryCount AS OwnerPostHistoryCount,
      ua.CommentCount AS OwnerCommentCount,
      ua.VoteCount AS OwnerVoteCount
    FROM
      PostLag pl
      LEFT OUTER JOIN UserActivity ua
        ON pl.OwnerUserId = ua.UserId
  )
SELECT
  upm.*,
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
  CONCAT(
    upm.PostTypeName,
    ' (',
    upm.PostScore,
    ') - ',
    COALESCE(upm.OwnerDisplayName, 'Community')
  ) AS PostSummary,
  upm.PostScore + upm.AnswerCount AS TotalEngagementScore,
  CASE
    WHEN upm.PostTypeName = 'Question' THEN upm.OwnerBadgeCount * 1.5
    WHEN upm.PostTypeName = 'Answer' THEN upm.OwnerBadgeCount * 1.2
    ELSE upm.OwnerBadgeCount
  END AS WeightedBadgeScore
FROM
  UserPostMetrics upm
WHERE
  upm.PostScore > 0
  OR upm.AnswerCount > 0
  OR upm.CommentCount > 0
UNION
SELECT
  NULL AS PostId,
  NULL AS OwnerUserId,
  'All' AS PostTypeName,
  SUM(PostScore) AS PostScore,
  SUM(AnswerCount) AS AnswerCount,
  SUM(CommentCount) AS CommentCount,
  SUM(FavoriteCount) AS FavoriteCount,
  NULL AS ClosedDate,
  SUM(CommentCountFromCommentsTable) AS CommentCountFromCommentsTable,
  SUM(EditCount) AS EditCount,
  SUM(VoteCount) AS VoteCount,
  CASE
    WHEN SUM(CASE WHEN ClosedDate IS NOT NULL THEN 1 ELSE 0 END) > 0 THEN 1
    ELSE 0
  END AS IsClosed,
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
  AVG(CASE
    WHEN PostTypeName = 'Question' THEN OwnerBadgeCount * 1.5
    WHEN PostTypeName = 'Answer' THEN OwnerBadgeCount * 1.2
    ELSE OwnerBadgeCount
  END) AS WeightedBadgeScore
FROM
  UserPostMetrics
GROUP BY
  ROLLUP(PostTypeName)
ORDER BY
  CASE
    WHEN PostTypeName = 'All' THEN 1
    ELSE 0
  END,
  PostScore DESC;

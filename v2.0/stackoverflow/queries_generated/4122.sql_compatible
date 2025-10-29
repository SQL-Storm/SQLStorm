WITH
  AnswerScores AS (
    SELECT
      p.Id AS PostId,
      SUM(v.VoteTypeId) AS TotalScore,
      COUNT(v.Id) AS TotalVotes,
      CASE
        WHEN COUNT(v.Id) > 0
        THEN CAST(SUM(v.VoteTypeId) AS DOUBLE PRECISION) / COUNT(v.Id)
        ELSE 0
      END AS AvgVoteType
    FROM Posts p
    JOIN Votes v
      ON p.Id = v.PostId
    WHERE
      p.PostTypeId = 2
      AND v.VoteTypeId IN (2, 3)
    GROUP BY
      p.Id
  ),
  QuestionEngagement AS (
    SELECT
      q.Id AS QuestionId,
      q.Title,
      q.CreationDate AS QuestionCreationDate,
      COALESCE(q.AnswerCount, 0) AS AnswerCount,
      COALESCE(q.CommentCount, 0) AS CommentCount,
      COALESCE(q.FavoriteCount, 0) AS FavoriteCount,
      COALESCE(q.ViewCount, 0) AS ViewCount,
      CASE WHEN q.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
      COALESCE(MAX(c.CreationDate), TIMESTAMP '1900-01-01') AS LastCommentDate,
      COALESCE(MAX(ph.CreationDate), TIMESTAMP '1900-01-01') AS LastHistoryDate,
      COALESCE(MAX(p_hist.CreationDate), TIMESTAMP '1900-01-01') AS LastPostHistoryDate
    FROM Posts q
    LEFT JOIN Comments c
      ON q.Id = c.PostId
    LEFT JOIN PostHistory ph
      ON q.Id = ph.PostId
    LEFT JOIN PostHistory p_hist
      ON q.Id = p_hist.PostId
    WHERE
      q.PostTypeId = 1
    GROUP BY
      q.Id,
      q.Title,
      q.CreationDate,
      q.AnswerCount,
      q.CommentCount,
      q.FavoriteCount,
      q.ViewCount,
      q.ClosedDate
  ),
  UserReputationRank AS (
    SELECT
      Id AS UserId,
      Reputation,
      CreationDate,
      ROW_NUMBER() OVER (ORDER BY Reputation DESC, CreationDate ASC) AS ReputationRank
    FROM Users
  ),
  TopAnswers AS (
    SELECT
      a.Id AS AnswerId,
      a.ParentId AS QuestionId,
      a.Score AS AnswerScore,
      COALESCE(ascores.TotalVotes, 0) AS TotalAnswerVotes,
      COALESCE(ascores.AvgVoteType, 0) AS AvgAnswerVoteType,
      a.CreationDate AS AnswerCreationDate,
      ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY COALESCE(ascores.TotalVotes, 0) DESC, a.Score DESC, a.CreationDate ASC) AS AnswerRank
    FROM Posts a
    LEFT JOIN AnswerScores ascores
      ON a.Id = ascores.PostId
    WHERE
      a.PostTypeId = 2
  )
SELECT
  qe.QuestionId,
  qe.Title,
  qe.QuestionCreationDate,
  qe.AnswerCount,
  qe.CommentCount,
  qe.FavoriteCount,
  qe.ViewCount,
  qe.IsClosed,
  CAST((EXTRACT(EPOCH FROM (qe.LastCommentDate - qe.QuestionCreationDate)) / 86400) AS INTEGER) AS DaysSinceLastComment,
  CAST((EXTRACT(EPOCH FROM (qe.LastHistoryDate - qe.QuestionCreationDate)) / 86400) AS INTEGER) AS DaysSinceLastPostHistoryEntry,
  CAST((EXTRACT(EPOCH FROM (qe.LastPostHistoryDate - qe.QuestionCreationDate)) / 86400) AS INTEGER) AS DaysSinceLastEdit,
  CASE
    WHEN qe.ViewCount > 10000 THEN 'High Traffic'
    WHEN qe.ViewCount > 1000 THEN 'Medium Traffic'
    ELSE 'Low Traffic'
  END AS TrafficCategory,
  CASE
    WHEN ta.AnswerRank = 1 THEN 'Best Answer'
    WHEN ta.AnswerRank <= 5 THEN 'Top 5 Answer'
    ELSE 'Other Answer'
  END AS AnswerQualityRank,
  COALESCE(usr.DisplayName, 'Unknown User') AS OwnerDisplayName,
  COALESCE(ur.Reputation, 0) AS OwnerReputation,
  ur.ReputationRank,
  CASE
    WHEN qe.LastCommentDate > qe.LastPostHistoryDate THEN 'Comment Activity Dominant'
    WHEN qe.LastPostHistoryDate > qe.LastCommentDate THEN 'Edit Activity Dominant'
    ELSE 'Balanced Activity'
  END AS ActivityDominance,
  CASE
    WHEN qe.Title LIKE '%tutorial%' OR qe.Title LIKE '%Tutorial%' OR qe.Title LIKE '%how to%' OR qe.Title LIKE '%How To%' THEN 'Instructional'
    WHEN qe.Title IS NULL THEN 'No Title'
    ELSE 'General'
  END AS TitleType,
  pa.Id AS AcceptedAnswerId,
  pa.Score AS AcceptedAnswerScore,
  COALESCE(pascores.TotalVotes, 0) AS AcceptedAnswerTotalVotes,
  CASE
    WHEN EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = qe.QuestionId AND pl.LinkTypeId = 3) THEN 'Has Duplicate Link'
    ELSE 'No Duplicate Link'
  END AS DuplicateLinkStatus,
  CASE
    WHEN EXISTS (
      SELECT 1
      FROM PostLinks pl_inner
      JOIN PostLinks pl_outer
        ON pl_inner.RelatedPostId = pl_outer.PostId
      WHERE
        pl_inner.PostId = qe.QuestionId AND pl_inner.LinkTypeId = 3 AND pl_outer.LinkTypeId = 3
    ) THEN 'Indirect Duplicate Chain'
    ELSE 'No Indirect Duplicate Chain'
  END AS IndirectDuplicateChainStatus
FROM QuestionEngagement qe
LEFT JOIN Posts u
  ON qe.QuestionId = u.Id
LEFT JOIN Users usr
  ON u.OwnerUserId = usr.Id
LEFT JOIN UserReputationRank ur
  ON usr.Id = ur.UserId
LEFT JOIN TopAnswers ta
  ON qe.QuestionId = ta.QuestionId AND ta.AnswerRank = 1
LEFT JOIN Posts pa
  ON qe.QuestionId = pa.ParentId AND pa.Id = pa.AcceptedAnswerId OR (pa.Id IS NOT NULL AND pa.Id = pa.AcceptedAnswerId) -- ensure accepted answer join resolves to accepted answer rows
LEFT JOIN AnswerScores pascores
  ON pa.Id = pascores.PostId
WHERE
  qe.ViewCount > 500
  AND qe.AnswerCount > 0
  AND qe.QuestionCreationDate >= DATE '2023-01-01'
  AND (usr.Id IS NOT NULL OR ur.ReputationRank IS NOT NULL)
ORDER BY
  qe.ViewCount DESC,
  qe.QuestionCreationDate DESC
FETCH FIRST 100 ROWS ONLY;
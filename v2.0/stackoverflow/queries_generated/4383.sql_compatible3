WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate,
      pht.Name AS PostHistoryTypeName,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    JOIN PostHistoryTypes pht
      ON ph.PostHistoryTypeId = pht.Id
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
  ),
  UserActivitySummary AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      COUNT(DISTINCT p.Id) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      SUM(CASE WHEN p.PostTypeId = 1 THEN COALESCE(p.FavoriteCount, 0) ELSE 0 END) AS QuestionFavorites,
      AVG(COALESCE(p.Score, 0)) AS AvgPostScore,
      MAX(COALESCE(p.ViewCount, 0)) AS MaxPostViewCount,
      COUNT(DISTINCT c.Id) AS CommentCount
    FROM Users u
    LEFT JOIN Posts p
      ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c
      ON u.Id = c.UserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate
  ),
  QuestionDetails AS (
    SELECT
      q.Id AS QuestionId,
      q.Title,
      q.CreationDate AS QuestionCreationDate,
      q.OwnerUserId,
      q.AcceptedAnswerId,
      q.AnswerCount,
      q.Score AS QuestionScore,
      q.ViewCount AS QuestionViewCount,
      q.ClosedDate,
      CASE WHEN q.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS QuestionStatus,
      q.Tags,
      ua.DisplayName AS OwnerDisplayName,
      ua.Reputation AS OwnerReputation,
      (
        SELECT
          COUNT(*)
        FROM Posts a
        WHERE
          a.ParentId = q.Id AND a.PostTypeId = 2
      ) AS ActualAnswerCount,
      (
        SELECT
          COUNT(*)
        FROM Comments qc
        WHERE
          qc.PostId = q.Id
      ) AS QuestionCommentCount,
      (
        SELECT
          COUNT(*)
        FROM PostLinks pl
        WHERE
          pl.PostId = q.Id AND pl.LinkTypeId = 3
      ) AS DuplicateLinkCount,
      (
        SELECT
          ph.Text
        FROM PostHistory ph
        WHERE
          ph.PostId = q.Id AND ph.PostHistoryTypeId = 1
        ORDER BY ph.CreationDate
        LIMIT 1
      ) AS InitialTitle,
      (
        SELECT
          STRING_AGG(t.TagName, ', ')
        FROM (
          SELECT UNNEST(string_to_array(SUBSTRING(q.Tags FROM 2 FOR (LENGTH(q.Tags) - 2)), '><')) AS TagName
        ) t
      ) AS FormattedTags
    FROM Posts q
    JOIN UserActivitySummary ua
      ON q.OwnerUserId = ua.UserId
    WHERE
      q.PostTypeId = 1
  ),
  UserPostInteractions AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.PostId END) AS UpVotesCount,
      COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.PostId END) AS DownVotesCount,
      COUNT(DISTINCT CASE WHEN v.VoteTypeId = 5 THEN v.PostId END) AS FavoriteCount,
      COUNT(DISTINCT CASE WHEN v.VoteTypeId = 6 THEN v.PostId END) AS CloseVotesCount,
      SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseActions,
      SUM(CASE WHEN ph.PostHistoryTypeId IN (12, 13) THEN 1 ELSE 0 END) AS DeleteActions
    FROM Users u
    LEFT JOIN Votes v
      ON u.Id = v.UserId
    LEFT JOIN PostHistory ph
      ON u.Id = ph.UserId
    WHERE
      v.VoteTypeId IS NOT NULL OR ph.PostHistoryTypeId IN (10, 12, 13)
    GROUP BY
      u.Id,
      u.DisplayName
  )
SELECT
  qd.QuestionId,
  qd.Title,
  qd.QuestionCreationDate,
  qd.QuestionStatus,
  qd.ClosedDate,
  qd.OwnerUserId,
  qd.OwnerDisplayName,
  qd.OwnerReputation,
  qd.AnswerCount AS ExpectedAnswerCount,
  qd.ActualAnswerCount,
  qd.QuestionScore,
  qd.QuestionViewCount,
  qd.FormattedTags,
  qd.DuplicateLinkCount,
  CASE
    WHEN qd.AcceptedAnswerId IS NULL THEN 'No Accepted Answer'
    WHEN (
      SELECT
        COUNT(*)
      FROM Posts a
      WHERE
        a.Id = qd.AcceptedAnswerId AND a.ParentId = qd.QuestionId
    ) = 1 THEN 'Accepted Answer Exists'
    ELSE 'Invalid Accepted Answer Reference'
  END AS AcceptedAnswerStatus,
  COALESCE(qpi.UpVotesCount, 0) AS UserUpVotes,
  COALESCE(qpi.DownVotesCount, 0) AS UserDownVotes,
  COALESCE(qpi.FavoriteCount, 0) AS UserFavoriteMarks,
  COALESCE(qpi.CloseVotesCount, 0) AS UserCloseVotes,
  COALESCE(qpi.CloseActions, 0) AS UserCloseActions,
  COALESCE(qpi.DeleteActions, 0) AS UserDeleteActions,
  (
    SELECT
      COUNT(DISTINCT rpe.UserId)
    FROM RankedPostEdits rpe
    WHERE
      rpe.PostId = qd.QuestionId AND rpe.rn = 1
  ) AS UniqueEditors,
  CASE
    WHEN qd.InitialTitle IS NULL THEN 'No Initial Title Recorded'
    WHEN CHAR_LENGTH(qd.InitialTitle) < 10 THEN 'Short Initial Title'
    WHEN CHAR_LENGTH(qd.InitialTitle) > 100 THEN 'Long Initial Title'
    ELSE 'Medium Initial Title'
  END AS InitialTitleLengthCategory,
  CASE
    WHEN qd.QuestionCommentCount > 50 THEN 'High Comment Activity'
    WHEN qd.QuestionCommentCount > 10 THEN 'Medium Comment Activity'
    ELSE 'Low Comment Activity'
  END AS CommentActivityLevel,
  EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - CAST(qd.QuestionCreationDate AS TIMESTAMP)))/86400.0 AS DaysSinceCreation,
  (qd.QuestionScore * 1.0) / NULLIF(qd.QuestionViewCount, 0) AS ScorePerViewRatio,
  (qd.OwnerDisplayName || ' (' || ua.Reputation || ')') AS OwnerInfo,
  REPLACE(qd.Tags, '><', ' | ') AS ReadableTags,
  CASE
    WHEN qd.ClosedDate IS NOT NULL AND (EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - CAST(qd.ClosedDate AS TIMESTAMP)))/3600.0) < 72 THEN 'Recently Closed'
    ELSE 'Not Recently Closed'
  END AS ClosureRecency
FROM QuestionDetails qd
LEFT JOIN UserPostInteractions qpi
  ON qd.OwnerUserId = qpi.UserId
LEFT JOIN Users ua
  ON qd.OwnerUserId = ua.Id
WHERE
  qd.QuestionViewCount > 1000
  AND qd.AnswerCount > 5
  AND qd.QuestionScore > 10
  AND qd.OwnerReputation > 5000
  AND qd.QuestionCreationDate < (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year')
  AND qd.FormattedTags LIKE '%sql%'
  AND qd.OwnerDisplayName NOT LIKE '%community%'
  AND qd.OwnerUserId IS NOT NULL
ORDER BY
  qd.QuestionScore DESC,
  qd.QuestionViewCount DESC;
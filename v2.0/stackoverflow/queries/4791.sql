WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      u.DisplayName AS EditorDisplayName,
      ph.CreationDate AS EditDate,
      ph.Comment AS EditComment,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    JOIN Users u
      ON ph.UserId = u.Id
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
  ),
  LatestPostInfo AS (
    SELECT
      p.Id AS PostId,
      p.Title,
      p.PostTypeId,
      pt.Name AS PostTypeName,
      p.OwnerUserId,
      u_owner.DisplayName AS OwnerDisplayName,
      p.LastEditDate,
      p.LastActivityDate,
      p.Score,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ClosedDate,
      CASE
        WHEN p.ClosedDate IS NOT NULL THEN EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - p.ClosedDate)) / 86400
        ELSE NULL
      END AS DaysSinceClosed,
      CASE
        WHEN p.OwnerUserId IS NOT NULL THEN COALESCE(u_owner.Reputation, 0)
        ELSE 0
      END AS OwnerReputation,
      CASE
        WHEN p.OwnerUserId IS NOT NULL THEN COALESCE(u_owner.Views, 0)
        ELSE 0
      END AS OwnerViews,
      ROW_NUMBER() OVER (ORDER BY p.LastActivityDate DESC) AS LastActivePostRank
    FROM Posts p
    LEFT JOIN PostTypes pt
      ON p.PostTypeId = pt.Id
    LEFT JOIN Users u_owner
      ON p.OwnerUserId = u_owner.Id
    WHERE
      p.PostTypeId IN (1, 2)
  ),
  UserVoteSummary AS (
    SELECT
      v.UserId,
      COUNT(CASE WHEN vt.Name = 'UpMod' THEN 1 END) AS UpVotesReceived,
      COUNT(CASE WHEN vt.Name = 'DownMod' THEN 1 END) AS DownVotesReceived,
      SUM(CASE WHEN vt.Name = 'AcceptedByOriginator' THEN 1 ELSE 0 END) AS AcceptedAnswers
    FROM Votes v
    JOIN VoteTypes vt
      ON v.VoteTypeId = vt.Id
    GROUP BY
      v.UserId
  ),
  QuestionAnswerMetrics AS (
    SELECT
      q.Id AS QuestionId,
      COUNT(a.Id) AS AnswerCountPerQuestion,
      SUM(CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END) AS IsAcceptedAnswer,
      AVG(a.Score) AS AvgAnswerScore,
      MAX(a.Score) AS MaxAnswerScore,
      MIN(a.Score) AS MinAnswerScore,
      COUNT(c.Id) AS CommentCountPerQuestion,
      q.Score AS QuestionScore,
      q.ViewCount AS QuestionViewCount,
      q.FavoriteCount AS QuestionFavoriteCount,
      -- Standard SQL substring (remove PostgreSQL FROM .. FOR and POSITION with FROM)
      -- Extract first tag between '<' and '>' assuming tags like '<tag1><tag2>'
      CAST(
        CASE
          WHEN q.Tags IS NULL THEN NULL
          WHEN POSITION('>' IN q.Tags) > 0 AND POSITION('<' IN q.Tags) > 0 THEN
            SUBSTRING(q.Tags FROM (POSITION('<' IN q.Tags) + 1) FOR (POSITION('>' IN q.Tags) - POSITION('<' IN q.Tags) - 1))
          ELSE NULL
        END AS VARCHAR(100)
      ) AS FirstTag,
      CASE
        WHEN q.OwnerUserId IS NOT NULL AND u_q.DisplayName LIKE '%user%' THEN 'Likely Anonymous User'
        WHEN q.OwnerUserId IS NULL THEN 'Community Owned'
        ELSE COALESCE(u_q.DisplayName, 'Unknown')
      END AS QuestionOwnerDisplayName,
      CASE
        WHEN q.OwnerUserId IS NOT NULL AND u_q.CreationDate < (q.CreationDate - INTERVAL '1' YEAR) THEN 'Old Account'
        WHEN q.OwnerUserId IS NOT NULL AND u_q.CreationDate >= (q.CreationDate - INTERVAL '1' YEAR) THEN 'New Account'
        ELSE 'No User Data'
      END AS QuestionOwnerAccountAgeCategory,
      DENSE_RANK() OVER (ORDER BY q.Score DESC) AS QuestionScoreRank,
      LAG(q.Score, 1, 0) OVER (ORDER BY q.CreationDate) AS PreviousQuestionScore
    FROM Posts q
    LEFT JOIN Posts a
      ON q.Id = a.ParentId
    LEFT JOIN Comments c
      ON q.Id = c.PostId
    LEFT JOIN Users u_q
      ON q.OwnerUserId = u_q.Id
    WHERE
      q.PostTypeId = 1
    GROUP BY
      q.Id,
      q.Title,
      q.PostTypeId,
      q.OwnerUserId,
      u_q.DisplayName,
      u_q.CreationDate,
      q.LastEditDate,
      q.LastActivityDate,
      q.Score,
      q.AnswerCount,
      q.CommentCount,
      q.FavoriteCount,
      q.ClosedDate,
      q.CommunityOwnedDate,
      q.Tags,
      q.ViewCount,
      q.CreationDate
  )
SELECT
  lpi.PostId,
  lpi.Title AS PostTitle,
  lpi.PostTypeName,
  lpi.OwnerDisplayName,
  lpi.OwnerReputation,
  lpi.OwnerViews,
  lpi.LastEditDate,
  rpe.EditDate AS LastEditDetailsDate,
  rpe.EditorDisplayName AS LastEditorDisplayName,
  rpe.EditComment AS LastEditDetailsComment,
  lpi.LastActivityDate,
  lpi.Score AS PostScore,
  lpi.AnswerCount AS PostAnswerCount,
  lpi.CommentCount AS PostCommentCount,
  lpi.FavoriteCount AS PostFavoriteCount,
  lpi.ClosedDate,
  lpi.DaysSinceClosed,
  qam.AnswerCountPerQuestion,
  qam.AvgAnswerScore,
  qam.MaxAnswerScore,
  qam.MinAnswerScore,
  qam.IsAcceptedAnswer,
  qam.CommentCountPerQuestion,
  qam.QuestionScore,
  qam.QuestionViewCount,
  qam.QuestionFavoriteCount,
  qam.FirstTag,
  qam.QuestionOwnerAccountAgeCategory,
  qam.QuestionScoreRank,
  qam.PreviousQuestionScore,
  COALESCE(uvs.UpVotesReceived, 0) AS TotalUpVotesReceivedByOwner,
  COALESCE(uvs.DownVotesReceived, 0) AS TotalDownVotesReceivedByOwner,
  COALESCE(uvs.AcceptedAnswers, 0) AS TotalAcceptedAnswersByOwner,
  CASE
    WHEN lpi.OwnerUserId IS NOT NULL AND EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = lpi.OwnerUserId AND b.Name LIKE '%Master%') THEN 'Has Master Badge'
    WHEN lpi.OwnerUserId IS NOT NULL AND EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = lpi.OwnerUserId AND b.Name LIKE '%Guru%') THEN 'Has Guru Badge'
    ELSE 'No High-Level Badge'
  END AS OwnerBadgeStatus,
  CASE
    WHEN qam.QuestionScore > 1000 AND qam.AnswerCountPerQuestion > 10 THEN 'Popular High-Scoring Question'
    WHEN lpi.Score < 0 AND lpi.PostTypeId = 1 THEN 'Negatively Scored Question'
    WHEN lpi.PostTypeId = 2 AND lpi.Score > 0 THEN 'Positively Scored Answer'
    ELSE 'Standard Post'
  END AS PostClassification,
  SUM(lpi.Score) OVER (PARTITION BY lpi.PostTypeName) AS TotalScoreByCategory,
  AVG(EXTRACT(EPOCH FROM lpi.LastActivityDate)) OVER () AS AveragePostLastActivityTimestamp,
  (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = lpi.PostId AND pl.LinkTypeId = 3) AS DuplicateLinksToThisPost,
  (SELECT COUNT(*) FROM PostLinks pl WHERE pl.RelatedPostId = lpi.PostId AND pl.LinkTypeId = 3) AS DuplicateLinksFromThisPost,
  CASE
    WHEN lpi.PostTypeName = 'Question' AND lpi.Score > 50 AND qam.AnswerCountPerQuestion > 0 AND qam.AvgAnswerScore > 5 THEN 'High Quality Question with Good Answers'
    WHEN lpi.PostTypeName = 'Answer' AND lpi.Score > 10 AND qam.IsAcceptedAnswer = 1 THEN 'Accepted High-Scoring Answer'
    ELSE 'Other'
  END AS AnswerQualityIndicator,
  CASE WHEN lpi.OwnerUserId IS NULL OR lpi.OwnerUserId = -1 THEN 'Community User' ELSE 'Registered User' END AS OwnerType
FROM LatestPostInfo lpi
LEFT JOIN RankedPostEdits rpe
  ON lpi.PostId = rpe.PostId AND rpe.rn = 1
LEFT JOIN QuestionAnswerMetrics qam
  ON lpi.PostId = qam.QuestionId
LEFT JOIN UserVoteSummary uvs
  ON lpi.OwnerUserId = uvs.UserId
WHERE
  lpi.PostTypeName IS NOT NULL AND lpi.OwnerDisplayName IS NOT NULL
  AND (lpi.Score > 0 OR lpi.AnswerCount > 0 OR lpi.CommentCount > 0)
  AND lpi.LastActivityDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '6' MONTH)
UNION ALL
SELECT
  lpi.PostId,
  lpi.Title AS PostTitle,
  lpi.PostTypeName,
  lpi.OwnerDisplayName,
  lpi.OwnerReputation,
  lpi.OwnerViews,
  lpi.LastEditDate,
  rpe.EditDate AS LastEditDetailsDate,
  rpe.EditorDisplayName AS LastEditorDisplayName,
  rpe.EditComment AS LastEditDetailsComment,
  lpi.LastActivityDate,
  lpi.Score AS PostScore,
  lpi.AnswerCount AS PostAnswerCount,
  lpi.CommentCount AS PostCommentCount,
  lpi.FavoriteCount AS PostFavoriteCount,
  lpi.ClosedDate,
  lpi.DaysSinceClosed,
  qam.AnswerCountPerQuestion,
  qam.AvgAnswerScore,
  qam.MaxAnswerScore,
  qam.MinAnswerScore,
  qam.IsAcceptedAnswer,
  qam.CommentCountPerQuestion,
  qam.QuestionScore,
  qam.QuestionViewCount,
  qam.QuestionFavoriteCount,
  qam.FirstTag,
  qam.QuestionOwnerAccountAgeCategory,
  qam.QuestionScoreRank,
  qam.PreviousQuestionScore,
  COALESCE(uvs.UpVotesReceived, 0) AS TotalUpVotesReceivedByOwner,
  COALESCE(uvs.DownVotesReceived, 0) AS TotalDownVotesReceivedByOwner,
  COALESCE(uvs.AcceptedAnswers, 0) AS TotalAcceptedAnswersByOwner,
  CASE
    WHEN lpi.OwnerUserId IS NOT NULL AND EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = lpi.OwnerUserId AND b.Name LIKE '%Master%') THEN 'Has Master Badge'
    WHEN lpi.OwnerUserId IS NOT NULL AND EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = lpi.OwnerUserId AND b.Name LIKE '%Guru%') THEN 'Has Guru Badge'
    ELSE 'No High-Level Badge'
  END AS OwnerBadgeStatus,
  CASE
    WHEN qam.QuestionScore > 1000 AND qam.AnswerCountPerQuestion > 10 THEN 'Popular High-Scoring Question'
    WHEN lpi.Score < 0 AND lpi.PostTypeId = 1 THEN 'Negatively Scored Question'
    WHEN lpi.PostTypeId = 2 AND lpi.Score > 0 THEN 'Positively Scored Answer'
    ELSE 'Standard Post'
  END AS PostClassification,
  SUM(lpi.Score) OVER (PARTITION BY lpi.PostTypeName) AS TotalScoreByCategory,
  AVG(EXTRACT(EPOCH FROM lpi.LastActivityDate)) OVER () AS AveragePostLastActivityTimestamp,
  (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = lpi.PostId AND pl.LinkTypeId = 3) AS DuplicateLinksToThisPost,
  (SELECT COUNT(*) FROM PostLinks pl WHERE pl.RelatedPostId = lpi.PostId AND pl.LinkTypeId = 3) AS DuplicateLinksFromThisPost,
  CASE
    WHEN lpi.PostTypeName = 'Question' AND qam.QuestionScore > 50 AND qam.AnswerCountPerQuestion > 0 AND qam.AvgAnswerScore > 5 THEN 'High Quality Question with Good Answers'
    WHEN lpi.PostTypeName = 'Answer' AND lpi.Score > 10 AND qam.IsAcceptedAnswer = 1 THEN 'Accepted High-Scoring Answer'
    ELSE 'Other'
  END AS AnswerQualityIndicator,
  CASE WHEN lpi.OwnerUserId IS NULL OR lpi.OwnerUserId = -1 THEN 'Community User' ELSE 'Registered User' END AS OwnerType
FROM LatestPostInfo lpi
LEFT JOIN RankedPostEdits rpe
  ON lpi.PostId = rpe.PostId AND rpe.rn = 1
LEFT JOIN QuestionAnswerMetrics qam
  ON lpi.PostId = qam.QuestionId
LEFT JOIN UserVoteSummary uvs
  ON lpi.OwnerUserId = uvs.UserId
WHERE
  lpi.PostTypeName IS NOT NULL AND lpi.OwnerDisplayName IS NOT NULL
  AND (lpi.Score > 0 OR lpi.AnswerCount > 0 OR lpi.CommentCount > 0)
  AND lpi.LastActivityDate <= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '6' MONTH)
ORDER BY
  LastActivityDate DESC
LIMIT 1000;
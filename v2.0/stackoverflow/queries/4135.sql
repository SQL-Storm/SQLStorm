WITH
  RankedQuestions AS (
    SELECT
      p.Id AS QuestionId,
      p.Title AS QuestionTitle,
      p.OwnerUserId,
      p.CreationDate AS QuestionCreationDate,
      p.Score AS QuestionScore,
      p.ViewCount AS QuestionViewCount,
      p.AnswerCount,
      p.FavoriteCount,
      ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.CreationDate DESC) AS ScoreRank,
      ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC, p.CreationDate DESC) AS ViewRank,
      ROW_NUMBER() OVER (ORDER BY p.FavoriteCount DESC, p.CreationDate DESC) AS FavoriteRank
    FROM Posts AS p
    WHERE
      p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL
  ),
  QuestionAnswers AS (
    SELECT
      a.ParentId AS QuestionId,
      COUNT(a.Id) AS AnswerCount,
      AVG(a.Score) AS AvgAnswerScore,
      MAX(a.Score) AS MaxAnswerScore,
      SUM(CASE WHEN a.OwnerUserId = q.OwnerUserId THEN 1 ELSE 0 END) AS OwnAnswers
    FROM Posts AS a
    JOIN RankedQuestions AS q
      ON a.ParentId = q.QuestionId
    WHERE
      a.PostTypeId = 2
    GROUP BY
      a.ParentId, q.OwnerUserId
  ),
  QuestionComments AS (
    SELECT
      c.PostId AS QuestionId,
      COUNT(c.Id) AS CommentCount,
      SUM(c.Score) AS TotalCommentScore,
      MAX(c.CreationDate) AS LastCommentDate
    FROM Comments AS c
    JOIN RankedQuestions AS q
      ON c.PostId = q.QuestionId
    GROUP BY
      c.PostId
  ),
  UserQuestionStats AS (
    SELECT
      rq.OwnerUserId,
      COUNT(rq.QuestionId) AS UserTotalQuestions,
      SUM(rq.QuestionScore) AS UserTotalScore,
      AVG(rq.QuestionScore) AS UserAvgScore,
      SUM(CASE WHEN rq.ScoreRank <= 10 THEN 1 ELSE 0 END) AS UserTop10ScoreQuestions,
      SUM(CASE WHEN rq.ViewRank <= 10 THEN 1 ELSE 0 END) AS UserTop10ViewQuestions,
      SUM(CASE WHEN rq.FavoriteRank <= 10 THEN 1 ELSE 0 END) AS UserTop10FavoriteQuestions
    FROM RankedQuestions AS rq
    GROUP BY
      rq.OwnerUserId
  ),
  LatestPostEdits AS (
    SELECT
      ph.PostId,
      MAX(ph.CreationDate) AS LastEditDate
    FROM PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) AND ph.UserId IS NOT NULL
    GROUP BY
      ph.PostId
  )
SELECT
  rq.QuestionId,
  rq.QuestionTitle,
  rq.QuestionCreationDate,
  rq.QuestionScore,
  rq.QuestionViewCount,
  COALESCE(qa.AnswerCount, 0) AS TotalAnswers,
  COALESCE(qa.AvgAnswerScore, 0) AS AvgAnswerScore,
  COALESCE(qa.MaxAnswerScore, 0) AS MaxAnswerScore,
  COALESCE(qa.OwnAnswers, 0) AS OwnAnswers,
  COALESCE(qc.CommentCount, 0) AS TotalComments,
  COALESCE(qc.TotalCommentScore, 0) AS TotalCommentScore,
  CASE
    WHEN qc.LastCommentDate IS NULL THEN 'Never Commented'
    WHEN qc.LastCommentDate > rq.QuestionCreationDate + INTERVAL '7' DAY THEN 'Recent Comment'
    ELSE 'Old Comment'
  END AS CommentActivity,
  u.DisplayName AS OwnerDisplayName,
  u.Reputation AS OwnerReputation,
  uqs.UserTotalQuestions,
  uqs.UserTotalScore,
  uqs.UserAvgScore,
  uqs.UserTop10ScoreQuestions,
  uqs.UserTop10ViewQuestions,
  uqs.UserTop10FavoriteQuestions,
  CASE
    WHEN lpe.LastEditDate IS NULL THEN 'No Edits'
    WHEN lpe.LastEditDate > rq.QuestionCreationDate + INTERVAL '30' DAY THEN 'Significant Delay Since Last Edit'
    ELSE 'Timely Edit'
  END AS EditLag,
  CASE
    WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN p.FavoriteCount > 100 THEN 'Highly Favorited'
    ELSE 'Standard'
  END AS QuestionStatus,
  p.Tags AS QuestionTags,
  p.AnswerCount AS DirectAnswerCount,
  p.CommentCount AS DirectCommentCount,
  p.FavoriteCount AS DirectFavoriteCount
FROM RankedQuestions AS rq
LEFT JOIN QuestionAnswers AS qa
  ON rq.QuestionId = qa.QuestionId
LEFT JOIN QuestionComments AS qc
  ON rq.QuestionId = qc.QuestionId
LEFT JOIN Users AS u
  ON rq.OwnerUserId = u.Id
LEFT JOIN UserQuestionStats AS uqs
  ON rq.OwnerUserId = uqs.OwnerUserId
LEFT JOIN LatestPostEdits AS lpe
  ON rq.QuestionId = lpe.PostId
JOIN Posts AS p
  ON rq.QuestionId = p.Id
WHERE
  rq.ScoreRank <= 100 OR rq.ViewRank <= 100 OR rq.FavoriteRank <= 100

UNION ALL

SELECT
  NULL AS QuestionId,
  NULL AS QuestionTitle,
  NULL AS QuestionCreationDate,
  NULL AS QuestionScore,
  NULL AS QuestionViewCount,
  NULL AS TotalAnswers,
  NULL AS AvgAnswerScore,
  NULL AS MaxAnswerScore,
  NULL AS OwnAnswers,
  NULL AS TotalComments,
  NULL AS TotalCommentScore,
  NULL AS CommentActivity,
  NULL AS OwnerDisplayName,
  NULL AS OwnerReputation,
  NULL AS UserTotalQuestions,
  NULL AS UserTotalScore,
  NULL AS UserAvgScore,
  NULL AS UserTop10ScoreQuestions,
  NULL AS UserTop10ViewQuestions,
  NULL AS UserTop10FavoriteQuestions,
  NULL AS EditLag,
  NULL AS QuestionStatus,
  NULL AS QuestionTags,
  NULL AS DirectAnswerCount,
  NULL AS DirectCommentCount,
  NULL AS DirectFavoriteCount;
-- {"query": "4866.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1304} 

WITH
  QuestionStats AS (
    SELECT
      p.Id AS QuestionId,
      p.Title,
      p.OwnerUserId,
      p.CreationDate AS QuestionCreationDate,
      p.Score AS QuestionScore,
      p.ViewCount AS QuestionViewCount,
      p.AnswerCount,
      p.FavoriteCount,
      p.ClosedDate,
      COUNT(c.Id) AS CommentCountOnQuestion,
      AVG(a.Score) AS AvgAnswerScore,
      MAX(a.Score) AS MaxAnswerScore,
      MIN(a.Score) AS MinAnswerScore,
      COUNT(DISTINCT ph.UserId) AS DistinctEditorsOfQuestion,
      SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount,
      MAX(ph.CreationDate) AS LastEditDate
    FROM
      Posts AS p
    LEFT JOIN
      Comments AS c
      ON p.Id = c.PostId
    LEFT JOIN
      Posts AS a
      ON p.Id = a.ParentId AND a.PostTypeId = 2 -- Only consider answers
    LEFT JOIN
      PostHistory AS ph
      ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 7, 8, 9)
    WHERE
      p.PostTypeId = 1 -- Only questions
    GROUP BY
      p.Id,
      p.Title,
      p.OwnerUserId,
      p.CreationDate,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      p.FavoriteCount,
      p.ClosedDate
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      COUNT(DISTINCT qs.QuestionId) AS QuestionsAnswered,
      SUM(qs.AvgAnswerScore) AS TotalAvgAnswerScore,
      COUNT(b.Id) AS BadgeCount,
      MAX(b.Date) AS LastBadgeDate,
      COUNT(DISTINCT c.PostId) AS CommentsMadeCount
    FROM
      Users AS u
    LEFT JOIN
      QuestionStats AS qs
      ON u.Id = qs.OwnerUserId
    LEFT JOIN
      Badges AS b
      ON u.Id = b.UserId
    LEFT JOIN
      Comments AS c
      ON u.Id = c.UserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate
  ),
  TopQuestions AS (
    SELECT
      qs.QuestionId,
      qs.Title,
      qs.QuestionScore,
      qs.QuestionViewCount,
      qs.AnswerCount,
      qs.FavoriteCount,
      qs.CommentCountOnQuestion,
      qs.AvgAnswerScore,
      qs.MaxAnswerScore,
      qs.MinAnswerScore,
      qs.DistinctEditorsOfQuestion,
      qs.EditCount,
      qs.LastEditDate,
      qs.OwnerUserId,
      ua.DisplayName AS OwnerDisplayName,
      ua.Reputation AS OwnerReputation,
      CASE WHEN qs.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
      DATEDIFF(day, qs.QuestionCreationDate, GETDATE()) AS DaysSinceCreation,
      ROW_NUMBER() OVER (ORDER BY qs.QuestionScore DESC, qs.QuestionViewCount DESC) AS RankByScoreView
    FROM
      QuestionStats AS qs
    LEFT JOIN
      UserActivity AS ua
      ON qs.OwnerUserId = ua.UserId
    WHERE
      qs.QuestionScore > 100 AND qs.AnswerCount > 5
  )
SELECT
  tq.QuestionId,
  tq.Title,
  tq.OwnerDisplayName,
  tq.OwnerReputation,
  tq.QuestionScore,
  tq.QuestionViewCount,
  tq.AnswerCount,
  tq.FavoriteCount,
  tq.CommentCountOnQuestion,
  tq.AvgAnswerScore,
  tq.MaxAnswerScore,
  tq.MinAnswerScore,
  tq.DistinctEditorsOfQuestion,
  tq.EditCount,
  tq.LastEditDate,
  tq.IsClosed,
  tq.DaysSinceCreation,
  tq.RankByScoreView,
  COALESCE(tq.OwnerReputation, 0) AS CoalescedOwnerReputation,
  IIF(tq.AvgAnswerScore > 50, 'High Average Answer Score', 'Standard Average Answer Score') AS AnswerScoreCategory,
  CASE
    WHEN tq.RankByScoreView <= 10 THEN 'Top 10 Question'
    WHEN tq.RankByScoreView <= 50 THEN 'Top 50 Question'
    ELSE 'Other Question'
  END AS QuestionTier,
  CONCAT(tq.OwnerDisplayName, ' (', ua.UserCreationDate, ')') AS OwnerInfo,
  (
    SELECT
      COUNT(pl.Id)
    FROM
      PostLinks AS pl
    WHERE
      pl.PostId = tq.QuestionId AND pl.LinkTypeId = 3 -- Duplicate link type
  ) AS DuplicateLinkCount
FROM
  TopQuestions AS tq
LEFT JOIN
  UserActivity AS ua
  ON tq.OwnerUserId = ua.UserId
WHERE
  tq.OwnerReputation > 10000 OR tq.QuestionScore > 500
ORDER BY
  tq.RankByScoreView;

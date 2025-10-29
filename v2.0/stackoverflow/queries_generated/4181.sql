-- {"query": "4181.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1438} 

WITH
  RankedQuestions AS (
    SELECT
      p.Id AS QuestionId,
      p.Title AS QuestionTitle,
      p.OwnerUserId,
      p.CreationDate AS QuestionCreationDate,
      p.Score AS QuestionScore,
      p.AnswerCount,
      p.FavoriteCount,
      ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.FavoriteCount DESC) AS RowNum
    FROM Posts AS p
    WHERE
      p.PostTypeId = 1 AND p.ClosedDate IS NULL
  ),
  UserQuestionStats AS (
    SELECT
      r.QuestionId,
      r.QuestionTitle,
      r.QuestionScore,
      r.AnswerCount,
      r.FavoriteCount,
      u.DisplayName AS OwnerDisplayName,
      DATEDIFF(day, u.CreationDate, r.QuestionCreationDate) AS DaysSinceOwnerCreation,
      CASE
        WHEN DATEDIFF(day, u.CreationDate, r.QuestionCreationDate) < 30 THEN 'New User'
        WHEN DATEDIFF(day, u.CreationDate, r.QuestionCreationDate) BETWEEN 30 AND 365 THEN 'Established User'
        ELSE 'Veteran User'
      END AS UserTenureCategory,
      (
        SELECT
          COUNT(ph.Id)
        FROM PostHistory AS ph
        WHERE
          ph.UserId = r.OwnerUserId AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6)
      ) AS UserPostEdits,
      (
        SELECT
          COUNT(b.Id)
        FROM Badges AS b
        WHERE
          b.UserId = r.OwnerUserId AND b.Class = 1
      ) AS UserGoldBadges,
      (
        SELECT
          COUNT(b.Id)
        FROM Badges AS b
        WHERE
          b.UserId = r.OwnerUserId AND b.Class = 2
      ) AS UserSilverBadges
    FROM RankedQuestions AS r
    LEFT OUTER JOIN Users AS u
      ON r.OwnerUserId = u.Id
    WHERE
      r.RowNum <= 100
  ),
  TopAnswers AS (
    SELECT
      p.Id AS AnswerId,
      p.ParentId AS QuestionId,
      p.OwnerUserId AS AnswerOwnerUserId,
      p.Score AS AnswerScore,
      p.CreationDate AS AnswerCreationDate,
      ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS AnswerRank
    FROM Posts AS p
    WHERE
      p.PostTypeId = 2 AND p.ParentId IN (SELECT QuestionId FROM RankedQuestions WHERE RowNum <= 100)
  ),
  QuestionAnswerDetails AS (
    SELECT
      uqs.QuestionId,
      uqs.QuestionTitle,
      uqs.OwnerDisplayName,
      uqs.UserTenureCategory,
      uqs.UserPostEdits,
      uqs.UserGoldBadges,
      uqs.UserSilverBadges,
      ta.AnswerId,
      ta.AnswerScore,
      ta.AnswerCreationDate,
      DATEDIFF(hour, uqs.QuestionCreationDate, ta.AnswerCreationDate) AS HoursToFirstTopAnswer,
      CASE
        WHEN ta.AnswerRank = 1 THEN 1
        ELSE 0
      END AS IsAcceptedAnswerIndicator
    FROM UserQuestionStats AS uqs
    INNER JOIN TopAnswers AS ta
      ON uqs.QuestionId = ta.QuestionId
    WHERE
      ta.AnswerRank <= 3
  )
SELECT
  qad.QuestionTitle,
  qad.OwnerDisplayName,
  qad.UserTenureCategory,
  qad.UserPostEdits,
  qad.UserGoldBadges,
  qad.UserSilverBadges,
  qad.AnswerScore,
  qad.AnswerCreationDate,
  qad.HoursToFirstTopAnswer,
  qad.IsAcceptedAnswerIndicator,
  (
    SELECT
      COUNT(c.Id)
    FROM Comments AS c
    WHERE
      c.PostId = qad.QuestionId AND c.CreationDate > qad.AnswerCreationDate
  ) AS CommentsAfterAnswer,
  COALESCE(pt.Name, 'Unknown') AS QuestionPostType,
  CASE
    WHEN qad.AnswerScore > 10 THEN 'High Scoring Answer'
    WHEN qad.AnswerScore > 0 THEN 'Medium Scoring Answer'
    ELSE 'Low Scoring Answer'
  END AS AnswerScoreCategory,
  (
    SELECT
      COUNT(pl.Id)
    FROM PostLinks AS pl
    WHERE
      pl.PostId = qad.QuestionId AND pl.LinkTypeId = 3
  ) AS DuplicateLinks
FROM QuestionAnswerDetails AS qad
LEFT OUTER JOIN PostTypes AS pt
  ON pt.Id = 1
WHERE
  qad.HoursToFirstTopAnswer BETWEEN 0 AND 72
UNION ALL
SELECT
  'Overall Metrics' AS QuestionTitle,
  NULL AS OwnerDisplayName,
  NULL AS UserTenureCategory,
  AVG(CAST(UserPostEdits AS REAL)) AS UserPostEdits,
  AVG(CAST(UserGoldBadges AS REAL)) AS UserGoldBadges,
  AVG(CAST(UserSilverBadges AS REAL)) AS UserSilverBadges,
  AVG(CAST(AnswerScore AS REAL)) AS AnswerScore,
  NULL AS AnswerCreationDate,
  AVG(CAST(HoursToFirstTopAnswer AS REAL)) AS HoursToFirstTopAnswer,
  AVG(CAST(IsAcceptedAnswerIndicator AS REAL)) AS IsAcceptedAnswerIndicator,
  AVG(CAST((
    SELECT
      COUNT(c.Id)
    FROM Comments AS c
    WHERE
      c.PostId = qad.QuestionId AND c.CreationDate > qad.AnswerCreationDate
  ) AS REAL)) AS CommentsAfterAnswer,
  NULL AS QuestionPostType,
  NULL AS AnswerScoreCategory,
  AVG(CAST((
    SELECT
      COUNT(pl.Id)
    FROM PostLinks AS pl
    WHERE
      pl.PostId = qad.QuestionId AND pl.LinkTypeId = 3
  ) AS REAL)) AS DuplicateLinks
FROM QuestionAnswerDetails AS qad;

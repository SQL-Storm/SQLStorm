-- {"query": "4372.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2429} 

WITH
  QuestionStats AS (
    SELECT
      p.Id AS QuestionId,
      p.Title AS QuestionTitle,
      p.OwnerUserId,
      u.DisplayName AS OwnerDisplayName,
      p.CreationDate AS QuestionCreationDate,
      p.Score AS QuestionScore,
      p.AnswerCount,
      p.FavoriteCount,
      p.ViewCount AS QuestionViewCount,
      p.Tags,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS QuestionNumberForUser,
      AVG(CAST(ph.CommentCount AS DECIMAL(10, 2))) OVER (PARTITION BY p.OwnerUserId) AS AvgCommentCountForUser,
      CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        ELSE 'Open'
      END AS QuestionStatus
    FROM Posts AS p
    LEFT JOIN Users AS u
      ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId = 1 -- Questions
  ),
  AnswerStats AS (
    SELECT
      p.Id AS AnswerId,
      p.ParentId AS QuestionId,
      p.OwnerUserId,
      u.DisplayName AS OwnerDisplayName,
      p.CreationDate AS AnswerCreationDate,
      p.Score AS AnswerScore,
      ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS AnswerRankForQuestion,
      LAG(p.Score, 1, 0) OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS PreviousAnswerScore
    FROM Posts AS p
    LEFT JOIN Users AS u
      ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId = 2 -- Answers
  ),
  UserBadgeCounts AS (
    SELECT
      UserId,
      COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
      COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
      COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges
    GROUP BY
      UserId
  ),
  PostActivity AS (
    SELECT
      PostId,
      COUNT(CASE WHEN PostHistoryTypeId = 5 THEN 1 END) AS BodyEdits,
      COUNT(CASE WHEN PostHistoryTypeId IN (1, 4, 7) THEN 1 END) AS TitleEdits,
      SUM(CASE WHEN PostHistoryTypeId = 2 THEN 1 ELSE 0 END) AS BodyRevisions
    FROM PostHistory
    WHERE
      PostHistoryTypeId IN (1, 2, 4, 5, 7)
    GROUP BY
      PostId
  ),
  CombinedData AS (
    SELECT
      qs.QuestionId,
      qs.QuestionTitle,
      qs.QuestionCreationDate,
      qs.QuestionScore,
      qs.AnswerCount,
      qs.FavoriteCount,
      qs.QuestionViewCount,
      qs.Tags,
      qs.QuestionStatus,
      qs.OwnerUserId,
      qs.OwnerDisplayName,
      qs.AvgCommentCountForUser,
      qs.QuestionNumberForUser,
      COALESCE(ans.AnswerId, -1) AS BestAnswerId,
      COALESCE(ans.OwnerDisplayName, 'Community') AS BestAnswererDisplayName,
      COALESCE(ans.AnswerScore, 0) AS BestAnswerScore,
      COALESCE(ans.AnswerCreationDate, '1900-01-01') AS BestAnswerCreationDate,
      COALESCE(ubc.GoldBadges, 0) AS OwnerGoldBadges,
      COALESCE(ubc.SilverBadges, 0) AS OwnerSilverBadges,
      COALESCE(ubc.BronzeBadges, 0) AS OwnerBronzeBadges,
      COALESCE(pa.BodyEdits, 0) AS TotalBodyEdits,
      COALESCE(pa.TitleEdits, 0) AS TotalTitleEdits,
      COALESCE(pa.BodyRevisions, 0) AS TotalBodyRevisions,
      DATEDIFF(day, qs.QuestionCreationDate, GETDATE()) AS DaysSinceCreation,
      qs.QuestionViewCount * 1.0 / (
        CASE
          WHEN DATEDIFF(day, qs.QuestionCreationDate, GETDATE()) = 0 THEN 1
          ELSE DATEDIFF(day, qs.QuestionCreationDate, GETDATE())
        END
      ) AS ViewsPerDay
    FROM QuestionStats AS qs
    LEFT JOIN AnswerStats AS ans
      ON qs.QuestionId = ans.QuestionId
      AND ans.AnswerRankForQuestion = 1
    LEFT JOIN UserBadgeCounts AS ubc
      ON qs.OwnerUserId = ubc.UserId
    LEFT JOIN PostActivity AS pa
      ON qs.QuestionId = pa.PostId
  )
SELECT
  cd.QuestionTitle,
  cd.OwnerDisplayName,
  cd.QuestionCreationDate,
  cd.QuestionScore,
  cd.AnswerCount,
  cd.FavoriteCount,
  cd.QuestionViewCount,
  cd.Tags,
  cd.QuestionStatus,
  cd.BestAnswererDisplayName,
  cd.BestAnswerScore,
  cd.OwnerGoldBadges,
  cd.OwnerSilverBadges,
  cd.OwnerBronzeBadges,
  cd.TotalBodyEdits,
  cd.TotalTitleEdits,
  cd.TotalBodyRevisions,
  cd.ViewsPerDay,
  CASE
    WHEN cd.OwnerGoldBadges > 100 THEN 'Elite'
    WHEN cd.OwnerSilverBadges > 500 THEN 'Renowned'
    WHEN cd.OwnerBronzeBadges > 1000 THEN 'Prolific'
    ELSE 'Standard'
  END AS UserTier,
  CASE
    WHEN cd.BestAnswerScore > 50 AND cd.TotalBodyEdits > 5 THEN 'Highly Valued Answer'
    WHEN cd.QuestionScore > 100 AND cd.AnswerCount > 10 THEN 'Popular Question'
    WHEN cd.ViewsPerDay > 100 THEN 'High Traffic Question'
    ELSE 'Regular Question'
  END AS QuestionCategory,
  (
    SELECT
      COUNT(*)
    FROM Comments AS c
    WHERE
      c.PostId = cd.QuestionId
      AND c.CreationDate BETWEEN cd.QuestionCreationDate AND DATEADD(day, 7, cd.QuestionCreationDate)
  ) AS CommentsInFirstWeek,
  IIF(cd.OwnerUserId IS NULL, 'Anonymous', u.DisplayName) AS PostOwnerDisplayName,
  IIF(
    cd.BestAnswererDisplayName <> 'Community' AND cd.BestAnswerScore > cd.QuestionScore,
    'High Score Answer',
    'Standard Score'
  ) AS AnswerVsQuestionScore,
  LEFT(cd.Tags, CHARINDEX('>', cd.Tags + '>') - 1) AS FirstTag,
  REPLACE(cd.QuestionTitle, '?', '!?') AS ModifiedTitle
FROM CombinedData AS cd
LEFT JOIN Users AS u
  ON cd.OwnerUserId = u.Id
WHERE
  cd.QuestionScore > 0
  AND cd.AnswerCount > 0
  AND cd.QuestionViewCount > 1000
  AND cd.OwnerGoldBadges + cd.OwnerSilverBadges + cd.OwnerBronzeBadges > 10
  AND cd.QuestionCreationDate > '2022-01-01'
UNION
SELECT
  qs.QuestionTitle,
  qs.OwnerDisplayName,
  qs.QuestionCreationDate,
  qs.QuestionScore,
  qs.AnswerCount,
  qs.FavoriteCount,
  qs.QuestionViewCount,
  qs.Tags,
  qs.QuestionStatus,
  'Community' AS BestAnswererDisplayName,
  0 AS BestAnswerScore,
  COALESCE(ubc.GoldBadges, 0) AS OwnerGoldBadges,
  COALESCE(ubc.SilverBadges, 0) AS OwnerSilverBadges,
  COALESCE(ubc.BronzeBadges, 0) AS OwnerBronzeBadges,
  COALESCE(pa.BodyEdits, 0) AS TotalBodyEdits,
  COALESCE(pa.TitleEdits, 0) AS TotalTitleEdits,
  COALESCE(pa.BodyRevisions, 0) AS TotalBodyRevisions,
  qs.QuestionViewCount * 1.0 / (
    CASE
      WHEN DATEDIFF(day, qs.QuestionCreationDate, GETDATE()) = 0 THEN 1
      ELSE DATEDIFF(day, qs.QuestionCreationDate, GETDATE())
    END
  ) AS ViewsPerDay,
  CASE
    WHEN ubc.GoldBadges > 100 THEN 'Elite'
    WHEN ubc.SilverBadges > 500 THEN 'Renowned'
    WHEN ubc.BronzeBadges > 1000 THEN 'Prolific'
    ELSE 'Standard'
  END AS UserTier,
  CASE
    WHEN qs.QuestionScore > 100 AND qs.AnswerCount > 10 THEN 'Popular Question'
    WHEN qs.QuestionViewCount > 10000 THEN 'High Traffic Question'
    ELSE 'Regular Question'
  END AS QuestionCategory,
  (
    SELECT
      COUNT(*)
    FROM Comments AS c
    WHERE
      c.PostId = qs.QuestionId
      AND c.CreationDate BETWEEN qs.QuestionCreationDate AND DATEADD(day, 7, qs.QuestionCreationDate)
  ) AS CommentsInFirstWeek,
  IIF(qs.OwnerUserId IS NULL, 'Anonymous', u.DisplayName) AS PostOwnerDisplayName,
  'Standard Score' AS AnswerVsQuestionScore,
  LEFT(qs.Tags, CHARINDEX('>', qs.Tags + '>') - 1) AS FirstTag,
  REPLACE(qs.QuestionTitle, '?', '!?') AS ModifiedTitle
FROM QuestionStats AS qs
LEFT JOIN UserBadgeCounts AS ubc
  ON qs.OwnerUserId = ubc.UserId
LEFT JOIN PostActivity AS pa
  ON qs.QuestionId = pa.PostId
LEFT JOIN Users AS u
  ON qs.OwnerUserId = u.Id
WHERE
  qs.AnswerCount = 0
  AND qs.QuestionScore > 10
  AND qs.QuestionViewCount > 500
  AND qs.QuestionCreationDate > '2023-01-01'
ORDER BY
  QuestionCreationDate DESC;

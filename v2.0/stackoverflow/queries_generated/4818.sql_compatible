WITH
  QuestionStats AS (
    SELECT
      p.Id AS QuestionId,
      p.OwnerUserId,
      p.Title,
      p.CreationDate,
      p.Score,
      p.AnswerCount,
      p.FavoriteCount,
      p.ViewCount,
      p.ClosedDate,
      u.DisplayName AS OwnerDisplayName,
      COUNT(DISTINCT c.Id) AS CommentCount,
      AVG(CAST(p_ans.Score AS NUMERIC)) AS AvgAnswerScore,
      ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.FavoriteCount DESC) AS RankByScoreAndFavorites,
      DENSE_RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS RankByDateForPostType
    FROM
      Posts AS p
      LEFT JOIN Users AS u
        ON p.OwnerUserId = u.Id
      LEFT JOIN Comments AS c
        ON p.Id = c.PostId
      LEFT JOIN Posts AS p_ans
        ON p.Id = p_ans.ParentId AND p_ans.PostTypeId = 2
    WHERE
      p.PostTypeId = 1
      AND p.Score > 0
      AND p.AnswerCount IS NOT NULL
      AND p.CreationDate > TIMESTAMP '2023-01-01'
    GROUP BY
      p.Id,
      p.OwnerUserId,
      p.Title,
      p.CreationDate,
      p.Score,
      p.AnswerCount,
      p.FavoriteCount,
      p.ViewCount,
      p.ClosedDate,
      u.DisplayName,
      p.PostTypeId
  ),
  UserContribution AS (
    SELECT
      p.OwnerUserId,
      COUNT(DISTINCT p.Id) AS TotalPosts,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
      AVG(CAST(p.Score AS NUMERIC)) AS AvgPostScore,
      MAX(p.CreationDate) AS LastPostDate,
      COUNT(DISTINCT b.Id) AS TotalBadges,
      SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
      SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
      SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM
      Posts AS p
      LEFT JOIN Badges AS b
        ON p.OwnerUserId = b.UserId
    WHERE
      p.OwnerUserId IS NOT NULL
      AND p.OwnerUserId <> -1
    GROUP BY
      p.OwnerUserId
  ),
  HighEngagementQuestions AS (
    SELECT
      qs.QuestionId,
      qs.Title,
      qs.OwnerDisplayName,
      qs.Score,
      qs.AnswerCount,
      qs.FavoriteCount,
      qs.ViewCount,
      qs.CreationDate,
      uc.TotalPosts AS OwnerTotalPosts,
      uc.TotalQuestions AS OwnerTotalQuestions,
      uc.TotalAnswers AS OwnerTotalAnswers,
      uc.AvgPostScore AS OwnerAvgPostScore,
      uc.GoldBadges AS OwnerGoldBadges,
      uc.SilverBadges AS OwnerSilverBadges,
      uc.BronzeBadges AS OwnerBronzeBadges,
      CASE
        WHEN qs.Score > 100 THEN 'High Score'
        WHEN qs.FavoriteCount > 50 THEN 'Highly Favorited'
        WHEN qs.AnswerCount > 20 THEN 'Highly Answered'
        ELSE 'Moderate Engagement'
      END AS EngagementLevel,
      (qs.Score * 1.0 / NULLIF(qs.ViewCount, 0)) AS ScorePerView,
      COALESCE(qs.ClosedDate, TIMESTAMP '1900-01-01') AS EffectiveClosedDate,
      CAST(DATE_PART('day', TIMESTAMP '2024-10-01 12:34:56' - qs.CreationDate) AS INT) AS DaysSinceCreation,
      CASE
        WHEN qs.ClosedDate IS NOT NULL THEN 'Closed'
        ELSE 'Open'
      END AS Status,
      ROW_NUMBER() OVER (PARTITION BY CASE WHEN qs.Score > 100 THEN 'High Score' WHEN qs.FavoriteCount > 50 THEN 'Highly Favorited' WHEN qs.AnswerCount > 20 THEN 'Highly Answered' ELSE 'Moderate Engagement' END ORDER BY qs.Score DESC) AS RankWithinEngagementLevel
    FROM
      QuestionStats AS qs
      INNER JOIN UserContribution AS uc
        ON qs.OwnerUserId = uc.OwnerUserId
    WHERE
      qs.RankByScoreAndFavorites <= 1000
  )
SELECT
  heq.Title,
  heq.OwnerDisplayName,
  heq.Score,
  heq.AnswerCount,
  heq.FavoriteCount,
  heq.ViewCount,
  heq.EngagementLevel,
  heq.OwnerTotalPosts,
  heq.OwnerTotalQuestions,
  heq.OwnerTotalAnswers,
  heq.OwnerAvgPostScore,
  heq.OwnerGoldBadges,
  heq.OwnerSilverBadges,
  heq.OwnerBronzeBadges,
  heq.ScorePerView,
  heq.Status,
  heq.DaysSinceCreation,
  pht.Name AS LastEditType,
  ph.Comment AS LastEditComment,
  CASE
    WHEN heq.OwnerDisplayName ~ '[A-Z]' THEN 'Contains Uppercase'
    ELSE 'No Uppercase'
  END AS OwnerNameCase,
  CASE
    WHEN LOWER(heq.Title) LIKE '%how%' OR LOWER(heq.Title) LIKE '%what%' OR LOWER(heq.Title) LIKE '%why%' THEN 'Interrogative Title'
    ELSE 'Declarative Title'
  END AS TitleQuestionType,
  COALESCE(p.Tags, 'No Tags') AS QuestionTags,
  GREATEST(heq.OwnerTotalPosts, heq.OwnerTotalQuestions, heq.OwnerTotalAnswers) AS MaxOwnerContribution,
  RANK() OVER (ORDER BY heq.FavoriteCount DESC, heq.Score DESC) AS GlobalRankByFavAndScore
FROM
  HighEngagementQuestions AS heq
LEFT JOIN Posts AS p
  ON heq.QuestionId = p.Id
LEFT JOIN PostHistory AS ph
  ON p.Id = ph.PostId
  AND ph.PostHistoryTypeId IN (4, 5, 6)
LEFT JOIN PostHistoryTypes AS pht
  ON ph.PostHistoryTypeId = pht.Id
WHERE
  heq.RankWithinEngagementLevel <= 50
  AND heq.EffectiveClosedDate < TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year'
  AND ph.CreationDate IS NOT NULL
GROUP BY
  heq.Title,
  heq.OwnerDisplayName,
  heq.Score,
  heq.AnswerCount,
  heq.FavoriteCount,
  heq.ViewCount,
  heq.EngagementLevel,
  heq.OwnerTotalPosts,
  heq.OwnerTotalQuestions,
  heq.OwnerTotalAnswers,
  heq.OwnerAvgPostScore,
  heq.OwnerGoldBadges,
  heq.OwnerSilverBadges,
  heq.OwnerBronzeBadges,
  heq.ScorePerView,
  heq.Status,
  heq.DaysSinceCreation,
  pht.Name,
  ph.Comment,
  p.Tags,
  heq.EffectiveClosedDate,
  heq.CreationDate,
  ph.Id
HAVING
  COUNT(ph.Id) > 0
ORDER BY
  heq.Score DESC,
  heq.FavoriteCount DESC
LIMIT 100;
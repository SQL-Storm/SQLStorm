-- {"query": "4886.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 913}
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
      ROW_NUMBER() OVER (ORDER BY p.FavoriteCount DESC, p.Score DESC) AS RankByFavorites,
      DENSE_RANK() OVER (
        PARTITION BY EXTRACT(YEAR FROM p.CreationDate), EXTRACT(MONTH FROM p.CreationDate)
        ORDER BY p.AnswerCount DESC
      ) AS RankByAnswersInMonth
    FROM Posts AS p
    WHERE
      p.PostTypeId = 1
      AND p.ClosedDate IS NULL
      AND p.CreationDate >= DATE '2023-01-01'
  ),
  UserAnswerStats AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
      SUM(p.Score) FILTER (WHERE p.PostTypeId = 2) AS TotalAnswerScore,
      AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AvgAnswerScore
    FROM Users AS u
    JOIN Posts AS p
      ON u.Id = p.OwnerUserId
    WHERE
      p.PostTypeId = 2
      AND p.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '1' YEAR)
    GROUP BY
      u.Id,
      u.DisplayName
  ),
  TopUsers AS (
    SELECT
      UserId
    FROM UserAnswerStats
    ORDER BY
      TotalAnswerScore DESC
    LIMIT 5
  ),
  UserBadges AS (
    SELECT
      b.UserId,
      b.Name AS BadgeName,
      b.Date AS BadgeDate,
      ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) AS LastBadgeRank
    FROM Badges AS b
    WHERE
      b.Class = 1
  )
SELECT
  rq.QuestionTitle,
  rq.QuestionScore,
  rq.AnswerCount,
  rq.RankByFavorites,
  rq.RankByAnswersInMonth,
  COALESCE(u.DisplayName, 'Anonymous') AS OwnerDisplayName,
  COALESCE(ua.AnswerCount, 0) AS UserTotalAnswers,
  COALESCE(ua.TotalAnswerScore, 0) AS UserTotalAnswerScore,
  COALESCE(ub.BadgeName, 'No Gold Badges') AS MostRecentGoldBadge,
  CASE
    WHEN rq.QuestionScore > 100 AND COALESCE(ua.AvgAnswerScore, 0) > 5 THEN 'Highly Rated Question with High Avg Answer Score'
    WHEN rq.RankByFavorites <= 10 THEN 'Top 10 Favorited Question'
    WHEN rq.RankByAnswersInMonth <= 5 THEN 'Top 5 Answered Question This Month'
    ELSE 'Standard Question'
  END AS QuestionCategory,
  (
    SELECT
      COUNT(c.Id)
    FROM Comments AS c
    WHERE
      c.PostId = rq.QuestionId
      AND c.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '30' DAY)
  ) AS RecentCommentCount,
  rq.QuestionId,
  rq.OwnerUserId
FROM RankedQuestions AS rq
LEFT JOIN Users AS u
  ON rq.OwnerUserId = u.Id
LEFT JOIN UserAnswerStats AS ua
  ON u.Id = ua.UserId
LEFT JOIN TopUsers AS tu
  ON u.Id = tu.UserId
LEFT JOIN UserBadges AS ub
  ON u.Id = ub.UserId
  AND ub.LastBadgeRank = 1
WHERE
  rq.QuestionScore > 0
  AND LENGTH(rq.QuestionTitle) > 10
  AND (rq.OwnerUserId IS NOT NULL OR rq.QuestionScore > 50)
GROUP BY
  rq.QuestionTitle,
  rq.QuestionScore,
  rq.AnswerCount,
  rq.RankByFavorites,
  rq.RankByAnswersInMonth,
  u.DisplayName,
  ua.AnswerCount,
  ua.TotalAnswerScore,
  ua.AvgAnswerScore,
  ub.BadgeName,
  rq.QuestionId,
  rq.OwnerUserId
ORDER BY
  rq.RankByFavorites,
  rq.QuestionScore DESC;
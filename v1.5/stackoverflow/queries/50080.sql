-- {"query": "50080.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1215} 
WITH PopularTags AS (
  SELECT
    TagName
  FROM Tags
  WHERE
    Count > 25000 AND IsRequired = false
), AnswerStats AS (
  SELECT
    a.Id AS AnswerId,
    a.OwnerUserId,
    a.ParentId AS QuestionId,
    a.Score AS AnswerScore,
    a.CreationDate AS AnswerCreationDate,
    q.AcceptedAnswerId,
    q.CreationDate AS QuestionCreationDate,
    q.Tags AS QuestionTags,
    q.ViewCount AS QuestionViewCount
  FROM Posts AS a
  JOIN Posts AS q
    ON a.ParentId = q.Id
  WHERE
    a.PostTypeId = 2
    AND q.PostTypeId = 1
    AND a.OwnerUserId IS NOT NULL
    AND q.ClosedDate IS NULL
    AND EXISTS (
      SELECT
        1
      FROM PopularTags pt
      WHERE
        q.Tags LIKE '%' || pt.TagName || '%'
    )
), UserContributions AS (
  SELECT
    OwnerUserId,
    COUNT(AnswerId) AS TotalAnswers,
    AVG(AnswerScore) AS AvgAnswerScore,
    SUM(AnswerScore) AS TotalAnswerScore,
    SUM(CASE WHEN AcceptedAnswerId = AnswerId THEN 1 ELSE 0 END) AS AcceptedAnswers,
    AVG(EXTRACT(EPOCH FROM (AnswerCreationDate - QuestionCreationDate))) AS AvgTimeToAnswerSeconds,
    SUM(QuestionViewCount) AS TotalQuestionViewsOnAnswers
  FROM AnswerStats
  GROUP BY
    OwnerUserId
), UserEngagement AS (
  SELECT
    UserId,
    SUM(CommentCount) AS TotalComments,
    SUM(EditCount) AS TotalEdits,
    SUM(GoldBadges) AS GoldBadges,
    SUM(SilverBadges) AS SilverBadges,
    SUM(BronzeBadges) AS BronzeBadges
  FROM (
    SELECT
      c.UserId,
      COUNT(c.Id) AS CommentCount,
      0 AS EditCount,
      0 AS GoldBadges,
      0 AS SilverBadges,
      0 AS BronzeBadges
    FROM Comments AS c
    WHERE
      c.UserId IS NOT NULL
    GROUP BY
      c.UserId
    UNION ALL
    SELECT
      ph.UserId,
      0 AS CommentCount,
      COUNT(ph.Id) AS EditCount,
      0 AS GoldBadges,
      0 AS SilverBadges,
      0 AS BronzeBadges
    FROM PostHistory AS ph
    WHERE
      ph.UserId IS NOT NULL AND ph.PostHistoryTypeId IN (4, 5, 6, 8)
    GROUP BY
      ph.UserId
    UNION ALL
    SELECT
      b.UserId,
      0 AS CommentCount,
      0 AS EditCount,
      SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
      SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
      SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges AS b
    WHERE
      b.UserId IS NOT NULL
    GROUP BY
      b.UserId
  ) AS EngagementData
  GROUP BY
    UserId
)
SELECT
  u.DisplayName,
  u.Reputation,
  u.CreationDate,
  uc.TotalAnswers,
  uc.AvgAnswerScore,
  uc.AcceptedAnswers,
  CAST(uc.AcceptedAnswers AS REAL) / uc.TotalAnswers AS AcceptanceRate,
  uc.AvgTimeToAnswerSeconds,
  uc.TotalQuestionViewsOnAnswers,
  ue.TotalComments,
  ue.TotalEdits,
  ue.GoldBadges,
  ue.SilverBadges,
  (
    (uc.TotalAnswerScore * 0.3) + (uc.AcceptedAnswers * 20) + (u.Reputation * 0.15) + (ue.TotalEdits * 0.25) + (ue.TotalComments * 0.1) + (ue.GoldBadges * 50) + (ue.SilverBadges * 25) - (uc.AvgTimeToAnswerSeconds / 3600)
  ) AS InfluenceScore,
  DENSE_RANK() OVER (ORDER BY (
    (uc.TotalAnswerScore * 0.3) + (uc.AcceptedAnswers * 20) + (u.Reputation * 0.15) + (ue.TotalEdits * 0.25) + (ue.TotalComments * 0.1) + (ue.GoldBadges * 50) + (ue.SilverBadges * 25) - (uc.AvgTimeToAnswerSeconds / 3600)
  ) DESC) AS UserRank
FROM Users AS u
JOIN UserContributions AS uc
  ON u.Id = uc.OwnerUserId
JOIN UserEngagement AS ue
  ON u.Id = ue.UserId
WHERE
  u.Reputation > 50000
  AND uc.TotalAnswers > 150
  AND uc.AcceptedAnswers > 20
  AND u.LastAccessDate > (cast('2024-10-01 12:34:56' as timestamp) - interval '1 year')
ORDER BY
  InfluenceScore DESC
LIMIT 100;
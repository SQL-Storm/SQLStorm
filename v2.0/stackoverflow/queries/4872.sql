WITH
  RankedQuestions AS (
    SELECT
      p.Id AS QuestionId,
      p.Title,
      p.OwnerUserId,
      p.CreationDate AS QuestionCreationDate,
      p.Score AS QuestionScore,
      p.AnswerCount,
      ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.CreationDate ASC) AS QuestionRank
    FROM Posts p
    WHERE
      p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL
  ),
  UserQuestionStats AS (
    SELECT
      rq.OwnerUserId,
      COUNT(rq.QuestionId) AS TotalQuestions,
      SUM(rq.QuestionScore) AS TotalQuestionScore,
      AVG(rq.QuestionScore) AS AvgQuestionScore,
      MAX(rq.QuestionCreationDate) AS LatestQuestionDate
    FROM RankedQuestions rq
    GROUP BY
      rq.OwnerUserId
  ),
  LatestAnswers AS (
    SELECT
      a.ParentId AS QuestionId,
      a.Id AS AnswerId,
      a.OwnerUserId AS AnswerOwnerUserId,
      a.CreationDate AS AnswerCreationDate,
      a.Score AS AnswerScore,
      ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.CreationDate DESC) AS rn
    FROM Posts a
    WHERE
      a.PostTypeId = 2 AND a.OwnerUserId IS NOT NULL
  ),
  TopAnswersPerQuestion AS (
    SELECT
      la.QuestionId,
      la.AnswerId,
      la.AnswerOwnerUserId,
      la.AnswerCreationDate,
      la.AnswerScore,
      la.rn
    FROM LatestAnswers la
    WHERE
      la.rn <= 3
  ),
  UserAnswerStats AS (
    SELECT
      ta.AnswerOwnerUserId,
      COUNT(ta.AnswerId) AS TotalAnswers,
      SUM(ta.AnswerScore) AS TotalAnswerScore,
      AVG(ta.AnswerScore) AS AvgAnswerScore
    FROM TopAnswersPerQuestion ta
    GROUP BY
      ta.AnswerOwnerUserId
  ),
  UserContributions AS (
    SELECT
      COALESCE(uqs.OwnerUserId, uas.AnswerOwnerUserId) AS UserId,
      COALESCE(uqs.TotalQuestions, 0) AS UserTotalQuestions,
      COALESCE(uqs.TotalQuestionScore, 0) AS UserTotalQuestionScore,
      COALESCE(uqs.AvgQuestionScore, 0.0) AS UserAvgQuestionScore,
      COALESCE(uas.TotalAnswers, 0) AS UserTotalAnswers,
      COALESCE(uas.TotalAnswerScore, 0) AS UserTotalAnswerScore,
      COALESCE(uas.AvgAnswerScore, 0.0) AS UserAvgAnswerScore,
      MAX(uqs.LatestQuestionDate) AS UserLatestQuestionDate
    FROM UserQuestionStats uqs
    FULL OUTER JOIN UserAnswerStats uas
      ON uqs.OwnerUserId = uas.AnswerOwnerUserId
    GROUP BY
      COALESCE(uqs.OwnerUserId, uas.AnswerOwnerUserId),
      COALESCE(uqs.TotalQuestions, 0),
      COALESCE(uqs.TotalQuestionScore, 0),
      COALESCE(uqs.AvgQuestionScore, 0.0),
      COALESCE(uas.TotalAnswers, 0),
      COALESCE(uas.TotalAnswerScore, 0),
      COALESCE(uas.AvgAnswerScore, 0.0)
  ),
  UserBadgeCounts AS (
    SELECT
      b.UserId,
      COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
      COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
      COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges b
    GROUP BY
      b.UserId
  ),
  UserPostLinkCounts AS (
    SELECT
      pl.PostId,
      COUNT(DISTINCT pl.RelatedPostId) AS LinkedPostCount
    FROM PostLinks pl
    WHERE
      pl.LinkTypeId = 1
    GROUP BY
      pl.PostId
  ),
  FinalResults AS (
    SELECT
      rq.QuestionId,
      rq.Title AS QuestionTitle,
      rq.QuestionRank,
      rq.AnswerCount AS QuestionAnswerCount,
      u.DisplayName AS OwnerDisplayName,
      u.Reputation AS OwnerReputation,
      u.CreationDate AS OwnerCreationDate,
      uc.UserTotalQuestions,
      uc.UserTotalAnswers,
      ubc.GoldBadges,
      ubc.SilverBadges,
      ubc.BronzeBadges,
      CASE
        WHEN u.WebsiteUrl IS NULL OR u.WebsiteUrl = '' THEN 'No Website'
        WHEN u.WebsiteUrl LIKE '%stackoverflow.com%' THEN 'Stack Overflow Related'
        ELSE 'External Website'
      END AS WebsiteCategory,
      pl.LinkedPostCount,
      DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS UserReputationRank,
      (
        (COALESCE(uc.UserTotalQuestionScore,0) + COALESCE(uc.UserTotalAnswerScore,0)) * (
          COALESCE(ubc.GoldBadges, 0) * 10 + COALESCE(ubc.SilverBadges, 0) * 5 + COALESCE(ubc.BronzeBadges, 0) * 1
        )
      ) AS WeightedPerformanceScore
    FROM RankedQuestions rq
    JOIN Users u
      ON rq.OwnerUserId = u.Id
    LEFT JOIN UserContributions uc
      ON u.Id = uc.UserId
    LEFT JOIN UserBadgeCounts ubc
      ON u.Id = ubc.UserId
    LEFT JOIN UserPostLinkCounts pl
      ON rq.QuestionId = pl.PostId
    WHERE
      rq.QuestionRank <= 1000 AND u.DownVotes < u.UpVotes * 5
  )
SELECT
  fr.QuestionId,
  fr.QuestionTitle,
  fr.QuestionRank,
  fr.QuestionAnswerCount,
  fr.OwnerDisplayName,
  fr.OwnerReputation,
  fr.OwnerCreationDate,
  fr.UserTotalQuestions,
  fr.UserTotalAnswers,
  fr.GoldBadges,
  fr.SilverBadges,
  fr.BronzeBadges,
  fr.WebsiteCategory,
  fr.LinkedPostCount,
  fr.UserReputationRank,
  fr.WeightedPerformanceScore,
  CASE
    WHEN fr.WeightedPerformanceScore > 1000000 THEN 'Elite'
    WHEN fr.WeightedPerformanceScore > 500000 THEN 'Veteran'
    WHEN fr.WeightedPerformanceScore > 100000 THEN 'Experienced'
    WHEN fr.WeightedPerformanceScore > 10000 THEN 'Intermediate'
    ELSE 'Novice'
  END AS PerformanceTier,
  (
    SELECT
      COUNT(*)
    FROM Comments c
    WHERE
      c.PostId = fr.QuestionId AND LENGTH(c.Text) > 100
  ) AS LongCommentsOnQuestion
FROM FinalResults fr
WHERE
  fr.OwnerReputation > 500
ORDER BY
  fr.WeightedPerformanceScore DESC,
  fr.QuestionRank ASC;
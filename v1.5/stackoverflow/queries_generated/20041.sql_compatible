WITH UserActivitySummary AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.AboutMe,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalQuestionScore,
    SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
    COUNT(c.Id) AS CommentCount,
    SUM(c.Score) AS TotalCommentScore,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE NULL END) AS TotalAnswersOnQuestions,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.FavoriteCount ELSE 0 END) AS TotalFavoritesOnQuestions
  FROM Users u
  LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.CommunityOwnedDate IS NULL
  LEFT JOIN Comments c ON u.Id = c.UserId
  WHERE u.Reputation > 500 AND u.Id > 0
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.AboutMe
),
UserBadgeAnalysis AS (
  SELECT
    b.UserId,
    COUNT(b.Id) AS TotalBadges,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
    MIN(CASE WHEN b.Class = 1 THEN b.Date ELSE NULL END) AS FirstGoldBadgeDate,
    MIN(CASE WHEN b.Name = 'Fanatic' THEN b.Date ELSE NULL END) AS FanaticBadgeDate
  FROM Badges b
  GROUP BY b.UserId
),
RankedUserPerformance AS (
  SELECT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.UserCreationDate,
    uas.TotalPosts,
    uas.QuestionCount,
    uas.AnswerCount,
    uas.CommentCount,
    COALESCE(uba.GoldBadges, 0) AS GoldBadges,
    COALESCE(uba.SilverBadges, 0) AS SilverBadges,
    COALESCE(uba.BronzeBadges, 0) AS BronzeBadges,
    (uas.TotalAnswerScore * 10) + (uas.TotalQuestionScore * 5) + (uas.Reputation) + (COALESCE(uba.GoldBadges, 0) * 1000) + (COALESCE(uba.SilverBadges, 0) * 100) AS PerformanceScore,
    uas.TotalAnswersOnQuestions / NULLIF(uas.QuestionCount, 0) AS AvgAnswersPerQuestion,
    LAG(uas.UserCreationDate, 1, uas.UserCreationDate) OVER (ORDER BY uas.UserCreationDate) AS PreviousUserCreationDate,
    CASE
        WHEN LOWER(uas.AboutMe) LIKE '%database%' OR LOWER(uas.AboutMe) LIKE '%sql%' THEN 'Database Specialist'
        WHEN LOWER(uas.AboutMe) LIKE '%python%' OR LOWER(uas.AboutMe) LIKE '%java%' OR LOWER(uas.AboutMe) LIKE '%c#%' THEN 'Developer'
        WHEN uas.AboutMe IS NULL THEN 'No Bio'
        ELSE 'Generalist'
    END AS UserProfileCategory,
    uba.FirstGoldBadgeDate - uas.UserCreationDate AS TimeToFirstGold,
    EXISTS (SELECT 1 FROM Votes v WHERE v.UserId = uas.UserId AND v.VoteTypeId = 5) AS HasFavorited
  FROM UserActivitySummary uas
  JOIN UserBadgeAnalysis uba ON uas.UserId = uba.UserId
  WHERE uas.AnswerCount > uas.QuestionCount AND uas.TotalPosts > 20
)
SELECT
  rup.DisplayName,
  rup.Reputation,
  rup.PerformanceScore,
  rup.UserProfileCategory,
  rup.QuestionCount,
  rup.AnswerCount,
  rup.CommentCount,
  rup.GoldBadges,
  rup.TimeToFirstGold,
  (
    SELECT crt.Name
    FROM PostHistory ph
    JOIN CloseReasonTypes crt ON CAST(ph.Comment AS INTEGER) = crt.Id
    WHERE ph.UserId = rup.UserId
      AND ph.PostHistoryTypeId = 10 -- Post Closed
    GROUP BY crt.Name
    ORDER BY COUNT(*) DESC
    LIMIT 1
  ) AS MostCommonCloseReason,
  (
    SELECT STRING_AGG(T.TagName, ', ')
    FROM (
      SELECT DISTINCT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
      FROM Posts p
      WHERE p.OwnerUserId = rup.UserId AND p.PostTypeId = 1 AND p.Tags IS NOT NULL
      LIMIT 5
    ) AS T
  ) AS TopTags,
  DENSE_RANK() OVER(PARTITION BY rup.UserProfileCategory ORDER BY rup.PerformanceScore DESC) AS RankInCategory,
  p_last.Title AS LastQuestionTitle,
  p_last.CreationDate AS LastQuestionDate,
  p_last.Score AS LastQuestionScore
FROM RankedUserPerformance rup
LEFT JOIN Posts p_last ON p_last.Id = (
  SELECT p_inner.Id
  FROM Posts p_inner
  WHERE p_inner.OwnerUserId = rup.UserId
    AND p_inner.PostTypeId = 1
  ORDER BY p_inner.CreationDate DESC
  LIMIT 1
)
WHERE rup.PerformanceScore > (SELECT AVG(PerformanceScore) FROM RankedUserPerformance)
  AND rup.TimeToFirstGold IS NOT NULL
ORDER BY rup.PerformanceScore DESC
LIMIT 100;
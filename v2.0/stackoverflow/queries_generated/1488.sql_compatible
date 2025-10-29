WITH UserAggregatedStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.Views AS UserProfileViews,
        u.Location,
        u.AboutMe,
        u.WebsiteUrl,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        COALESCE(SUM(p.ViewCount), 0) AS TotalPostViews,
        COUNT(DISTINCT c.Id) AS TotalComments,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) AS AvgQuestionScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) AS AvgAnswerScore,
        MAX(p.LastActivityDate) AS LastPostActivityDate,
        MIN(p.CreationDate) AS FirstPostDate,
        SUM(CASE WHEN p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '6 months' THEN 1 ELSE 0 END) AS RecentPostCount,
        SUM(CASE WHEN p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '6 months' THEN p.Score ELSE 0 END) AS RecentPostScore,
        MAX(CASE WHEN p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '6 months' THEN p.CreationDate ELSE NULL END) AS LatestRecentPostDate,
        RANK() OVER (ORDER BY u.Reputation DESC) AS GlobalReputationRank,
        NTILE(10) OVER (ORDER BY COALESCE(SUM(p.Score), 0) DESC) AS TotalScoreTier
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Views, u.Location, u.AboutMe, u.WebsiteUrl
),
UserSelfEditMetrics AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(ph.Id) AS TotalSelfEdits,
        AVG(EXTRACT(EPOCH FROM (ph.CreationDate - p.CreationDate)) / (60 * 60 * 24)) AS AvgDaysToFirstEdit
    FROM Posts p
    INNER JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
      AND ph.UserId = p.OwnerUserId
    GROUP BY p.OwnerUserId
),
UserBadgeAggregates AS (
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(b.Date) AS LastBadgeAwardDate
    FROM Badges b
    GROUP BY b.UserId
),
UsersWithHighReputationAndRecentActivity AS (
    SELECT
        u.UserId,
        u.DisplayName,
        u.Reputation,
        'HighReputation' AS UserCategory
    FROM UserAggregatedStats u
    WHERE u.Reputation > 10000
      AND u.RecentPostCount > 5
      AND u.TotalQuestions > 10
),
UsersWithManyAcceptedAnswersOrHighScoreAnswers AS (
    SELECT
        u.UserId,
        u.DisplayName,
        u.Reputation,
        'AnswerExpert' AS UserCategory
    FROM UserAggregatedStats u
    WHERE u.TotalAnswers > 50
      AND COALESCE(u.AvgAnswerScore, 0) > 5
      AND EXISTS (
            SELECT 1
            FROM Posts a
            WHERE a.OwnerUserId = u.UserId
              AND a.PostTypeId = 2
              AND a.Id = (SELECT q.AcceptedAnswerId FROM Posts q WHERE q.AcceptedAnswerId = a.Id LIMIT 1)
        )
),
CombinedInterestingUsers AS (
    SELECT * FROM UsersWithHighReputationAndRecentActivity
    UNION ALL
    SELECT * FROM UsersWithManyAcceptedAnswersOrHighScoreAnswers
)
SELECT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    ci.UserCategory,
    uas.TotalPosts,
    uas.TotalQuestions,
    uas.TotalAnswers,
    uas.TotalPostScore,
    uas.TotalComments,
    COALESCE(usm.TotalSelfEdits, 0) AS SelfEditCount,
    COALESCE(usm.AvgDaysToFirstEdit, 0.0) AS AvgDaysToFirstSelfEdit,
    COALESCE(uba.GoldBadges, 0) AS GoldBadges,
    COALESCE(uba.SilverBadges, 0) AS SilverBadges,
    COALESCE(uba.BronzeBadges, 0) AS BronzeBadges,
    (COALESCE(uba.GoldBadges, 0) * 100 + COALESCE(uba.SilverBadges, 0) * 10 + COALESCE(uba.BronzeBadges, 0)) AS BadgeWeightedScore,
    uas.RecentPostCount,
    uas.RecentPostScore,
    -- Format timestamp to a standard string using TO_CHAR alternative: use CAST to CHAR(19) in ISO format where supported
    -- Use TO_CHAR only if available; to maximize compatibility, use CAST(... AS VARCHAR)
    CAST(uas.LatestRecentPostDate AS VARCHAR) AS LatestRecentActivity,
    uas.GlobalReputationRank,
    uas.TotalScoreTier,
    (
        (uas.TotalPostScore * 0.6) + (uas.TotalComments * 0.2) + (uas.UserProfileViews * 0.05) +
        (COALESCE(uba.GoldBadges,0) * 100)
    ) / (EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - uas.UserCreationDate)) / (365.25 * 24 * 60 * 60) + 1) AS WeightedAnnualImpactScore,
    EXISTS (
        SELECT 1
        FROM Posts ans
        INNER JOIN Posts qst ON ans.ParentId = qst.Id
        WHERE ans.OwnerUserId = uas.UserId
          AND ans.PostTypeId = 2
          AND qst.PostTypeId = 1
          AND qst.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
          AND qst.Tags IS NOT NULL
          AND EXISTS (
                SELECT 1
                FROM Posts user_q
                WHERE user_q.OwnerUserId = uas.UserId
                  AND user_q.PostTypeId = 1
                  AND user_q.Tags IS NOT NULL
                  AND user_q.Tags LIKE '%' || SPLIT_PART(SUBSTRING(qst.Tags FROM 2 FOR LENGTH(qst.Tags)-2), '><', 1) || '%'
            )
    ) AS AnswersTaggedWithOwnQuestionTag,
    (
        SELECT COALESCE(AVG(p_linked.Score), 0)
        FROM Posts p_linked
        INNER JOIN PostLinks pl ON p_linked.Id = pl.PostId
        WHERE p_linked.OwnerUserId = uas.UserId
          AND pl.LinkTypeId = 1
          AND pl.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '2 years'
    ) AS AvgScoreOfRecentLinkedPosts,
    AVG(uas.TotalPostScore) OVER (PARTITION BY uas.TotalScoreTier ORDER BY uas.Reputation DESC ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING) AS AvgTotalScoreInTier,
    COALESCE(LOWER(SUBSTRING(TRIM(BOTH '>' FROM TRIM(BOTH '<' FROM SPLIT_PART(uas.AboutMe, '>', 1))), 1, 100)), 'About me not provided or too short') AS AboutMeSummary,
    CASE
        WHEN uas.WebsiteUrl IS NOT NULL AND uas.WebsiteUrl LIKE 'https://%' THEN 'Secure Website'
        WHEN uas.WebsiteUrl IS NOT NULL THEN 'Insecure Website'
        ELSE 'No Website'
    END AS WebsiteSecurityStatus,
    (
        SELECT COUNT(DISTINCT q.Id)
        FROM Posts q
        WHERE q.OwnerUserId = uas.UserId
          AND q.PostTypeId = 1
          AND q.AcceptedAnswerId IS NOT NULL
          AND q.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
    ) AS AcceptedAnswersForOwnRecentQuestionsCount,
    (
        SELECT COALESCE(c_top.Text, 'N/A')
        FROM Comments c_top
        INNER JOIN Posts p_c ON c_top.PostId = p_c.Id
        WHERE p_c.OwnerUserId = uas.UserId
        ORDER BY c_top.Score DESC, c_top.CreationDate DESC
        LIMIT 1
    ) AS TopCommentOnUsersPosts
FROM CombinedInterestingUsers ci
INNER JOIN UserAggregatedStats uas ON ci.UserId = uas.UserId
LEFT JOIN UserSelfEditMetrics usm ON uas.UserId = usm.UserId
LEFT JOIN UserBadgeAggregates uba ON uas.UserId = uba.UserId
WHERE uas.LastPostActivityDate IS NOT NULL
  AND uas.LastPostActivityDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '3 years'
  AND (uas.Location IS NULL OR (uas.Location NOT ILIKE '%test%' AND uas.Location NOT ILIKE '%fictional%'))
  AND (
        uas.AboutMe ILIKE '%developer%'
        OR uas.AboutMe ILIKE '%programmer%'
        OR uas.AboutMe ILIKE '%engineer%'
        OR uas.DisplayName ILIKE '%dev%'
        OR uas.DisplayName ILIKE '%code%'
      )
ORDER BY
    WeightedAnnualImpactScore DESC,
    uas.Reputation DESC,
    uas.UserId
LIMIT 200;
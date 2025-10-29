WITH UserPostStats AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS TotalQuestions,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS TotalAnswers,
        SUM(p.Score) AS TotalPostScore,
        SUM(COALESCE(p.ViewCount, 0)) AS TotalPostViews,
        MAX(p.CreationDate) AS LatestPostDate,
        MIN(p.CreationDate) AS FirstPostDate,
        AVG(CASE WHEN p.PostTypeId = 2 AND p.ParentId IS NOT NULL THEN p.Score END) AS AvgAnswerScore,
        COUNT(DISTINCT q.Id) FILTER (WHERE p.PostTypeId = 2 AND q.AcceptedAnswerId = p.Id) AS AcceptedAnswerCount
    FROM Posts p
    LEFT JOIN Posts q ON p.ParentId = q.Id
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
    HAVING COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) > 0 AND COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) > 0
),
UserBadgeAwards AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
PostHistoryAggregated AS (
    SELECT
        ph.PostId,
        COUNT(ph.Id) AS TotalHistoryEvents,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN 1 END) AS EditCount,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 END) AS CloseEventCount,
        COUNT(DISTINCT ph.UserId) AS DistinctEditors,
        MAX(ph.CreationDate) AS LatestPostHistoryDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 10, 11, 12, 13, 14, 15)
    GROUP BY ph.PostId
),
UserAllPostsOrdered AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId AS UserId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.ParentId,
        q_parent.AcceptedAnswerId,
        LAG(p.CreationDate, 1, TIMESTAMP '1900-01-01 00:00:00') OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevPostCreationDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId, p.PostTypeId ORDER BY
            CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE p.Score END DESC,
            p.CreationDate DESC
        ) AS PostRankByType
    FROM Posts p
    LEFT JOIN Posts q_parent ON p.PostTypeId = 2 AND p.ParentId = q_parent.Id
    WHERE p.OwnerUserId IN (SELECT UserId FROM UserPostStats)
      AND p.PostTypeId IN (1, 2)
),
UserTopPostsSummary AS (
    SELECT
        uap.UserId,
        STRING_AGG(CASE WHEN uap.PostTypeId = 1 AND uap.PostRankByType <= 3 THEN
            'Q' || uap.PostRankByType || ': "' || COALESCE(uap.Title, 'Untitled Question') || '" (V:' || COALESCE(uap.ViewCount, 0) || ',S:' || uap.Score || ', Edits:' || COALESCE(phag.EditCount, 0) || ', Tags: [' || COALESCE(TRIM(BOTH '>' FROM TRIM(BOTH '<' FROM REPLACE(REPLACE(uap.Tags, '><', ', '), '<', ''))), 'No Tags') || '])'
        END, '; ' ORDER BY uap.PostRankByType) FILTER (WHERE uap.PostTypeId = 1 AND uap.PostRankByType <= 3) AS Top3QuestionsSummary,
        STRING_AGG(CASE WHEN uap.PostTypeId = 2 AND uap.PostRankByType <= 3 THEN
            'A' || uap.PostRankByType || ': "' || COALESCE(SUBSTRING(uap.Title FROM 1 FOR 50) || CASE WHEN LENGTH(uap.Title) > 50 THEN '...' ELSE '' END, 'No Title') || '" (S:' || uap.Score || ', Accepted:' || CASE WHEN uap.PostId = uap.AcceptedAnswerId THEN 'Yes' ELSE 'No' END || ', Edits:' || COALESCE(phag.EditCount, 0) || ')'
        END, '; ' ORDER BY uap.PostRankByType) FILTER (WHERE uap.PostTypeId = 2 AND uap.PostRankByType <= 3) AS Top3AnswersSummary,
        AVG(CASE WHEN uap.PrevPostCreationDate != TIMESTAMP '1900-01-01 00:00:00' THEN EXTRACT(EPOCH FROM (uap.CreationDate - uap.PrevPostCreationDate))/86400.0 ELSE NULL END) AS AvgDaysBetweenPosts
    FROM UserAllPostsOrdered uap
    LEFT JOIN PostHistoryAggregated phag ON uap.PostId = phag.PostId
    GROUP BY uap.UserId
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate AS UserLastAccessDate,
    u.Location,
    COALESCE(ups.TotalQuestions, 0) AS UserTotalQuestions,
    COALESCE(ups.TotalAnswers, 0) AS UserTotalAnswers,
    COALESCE(ups.TotalPostScore, 0) AS UserTotalPostScore,
    COALESCE(ups.TotalPostViews, 0) AS UserTotalPostViews,
    ups.LatestPostDate,
    EXTRACT(YEAR FROM u.CreationDate) AS UserCreationYear,
    (u.Reputation * 0.5 + COALESCE(ups.TotalPostScore, 0) * 0.2 + COALESCE(uba.GoldBadges, 0) * 100 + COALESCE(uba.SilverBadges, 0) * 50 + COALESCE(uba.BronzeBadges, 0) * 10 + COALESCE(ups.AcceptedAnswerCount, 0) * 75) AS UserImpactScore,
    DENSE_RANK() OVER (ORDER BY (u.Reputation * 0.5 + COALESCE(ups.TotalPostScore, 0) * 0.2 + COALESCE(uba.GoldBadges, 0) * 100 + COALESCE(uba.SilverBadges, 0) * 50 + COALESCE(uba.BronzeBadges, 0) * 10 + COALESCE(ups.AcceptedAnswerCount, 0) * 75) DESC) AS UserImpactRank,
    NULLIF(EXTRACT(DAY FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - u.CreationDate)), 0) AS AccountAgeInDays,
    NULLIF(uba.LastBadgeDate, TIMESTAMP '1900-01-01 00:00:00') AS UserLastBadgeDate,
    COALESCE(uba.GoldBadges, 0) AS UserGoldBadges,
    COALESCE(uba.SilverBadges, 0) AS UserSilverBadges,
    COALESCE(uba.BronzeBadges, 0) AS UserBronzeBadges,
    (SELECT MIN(c.CreationDate) FROM Comments c JOIN Posts p_sub ON c.PostId = p_sub.Id WHERE p_sub.OwnerUserId = u.Id AND c.UserId IS NOT NULL) AS EarliestCommentDateOnUserPost,
    utps.AvgDaysBetweenPosts,
    COALESCE(ups.AvgAnswerScore, 0) AS UserAvgAnswerScore,
    COALESCE(
        (SELECT AVG(p_q.Score) FROM Posts p_q WHERE p_q.OwnerUserId = u.Id AND p_q.PostTypeId = 1),
        0
    ) AS UserAvgQuestionScore,
    utps.Top3QuestionsSummary,
    utps.Top3AnswersSummary,
    EXISTS (SELECT 1 FROM PostHistory ph_close WHERE ph_close.PostId IN (SELECT p_user.Id FROM Posts p_user WHERE p_user.OwnerUserId = u.Id) AND ph_close.PostHistoryTypeId = 10 AND ph_close.Comment ILIKE 'CloseReasonType: Community%') AS HasCommunityClosedPost,
    CASE
        WHEN u.Location IS NULL OR TRIM(u.Location) = '' OR LENGTH(TRIM(u.Location)) < 3 THEN 'Unknown / Unspecified'
        WHEN u.Location ILIKE '%United States%' OR u.Location ILIKE '%USA%' OR u.Location ILIKE '%America%' THEN 'USA Based'
        WHEN u.Location ILIKE '%India%' OR u.Location ILIKE '%Germany%' OR u.Location ILIKE '%UK%' OR u.Location ILIKE '%Canada%' THEN 'International - Major Tech Hub Region'
        ELSE 'International - Other'
    END AS UserLocationCategory,
    NTILE(4) OVER (ORDER BY u.Reputation DESC) AS ReputationQuartile,
    EXISTS (
        SELECT 1
        FROM Posts p_pop_long
        WHERE p_pop_long.OwnerUserId = u.Id
          AND p_pop_long.PostTypeId = 1
          AND p_pop_long.ViewCount > 50000
          AND LENGTH(COALESCE(p_pop_long.Body, '')) > 10000
          AND p_pop_long.Score > 50
    ) AS HasVeryPopularLongQuestion
FROM Users u
JOIN UserPostStats ups ON u.Id = ups.UserId
LEFT JOIN UserBadgeAwards uba ON u.Id = uba.UserId
LEFT JOIN UserTopPostsSummary utps ON u.Id = utps.UserId
WHERE u.Reputation > 500
  AND u.LastAccessDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '6 months'
ORDER BY
    UserImpactRank ASC, u.Reputation DESC, u.CreationDate ASC
LIMIT 500;
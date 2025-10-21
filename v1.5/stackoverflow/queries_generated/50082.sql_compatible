WITH UserActivity AS (
    SELECT
        UserId,
        COUNT(*) AS ActivityCount
    FROM (
        SELECT OwnerUserId AS UserId FROM Posts WHERE OwnerUserId IS NOT NULL
        UNION ALL
        SELECT UserId FROM Comments WHERE UserId IS NOT NULL
        UNION ALL
        SELECT UserId FROM Votes WHERE UserId IS NOT NULL AND VoteTypeId IN (2, 3, 5, 8)
    ) AS AllActivities
    GROUP BY UserId
    ORDER BY ActivityCount DESC
    LIMIT 100
),
UserPostMetrics AS (
    SELECT
        p.OwnerUserId,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS AvgAnswerScore,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS TotalQuestions,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS TotalAnswers,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount END) AS TotalQuestionViews,
        SUM(p.FavoriteCount) AS TotalFavorites
    FROM Posts p
    INNER JOIN UserActivity ua ON p.OwnerUserId = ua.UserId
    GROUP BY p.OwnerUserId
),
UserBadgeMetrics AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges b
    INNER JOIN UserActivity ua ON b.UserId = ua.UserId
    GROUP BY b.UserId
),
AcceptedAnswerMetrics AS (
    SELECT
        ans.OwnerUserId,
        COUNT(ans.Id) AS AcceptedAnswerCount,
        AVG(EXTRACT(EPOCH FROM (ans.CreationDate - q.CreationDate)) / 3600.0) AS AvgTimeToAcceptance
    FROM Posts AS ans
    INNER JOIN Posts AS q ON ans.Id = q.AcceptedAnswerId
    WHERE ans.OwnerUserId IN (SELECT UserId FROM UserActivity) AND ans.PostTypeId = 2
    GROUP BY ans.OwnerUserId
),
EditMetrics AS (
    SELECT
        ph.UserId,
        COUNT(*) AS TotalEdits,
        COUNT(DISTINCT ph.PostId) AS UniquePostsEdited
    FROM PostHistory ph
    INNER JOIN UserActivity ua ON ph.UserId = ua.UserId
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Body, Tags
    GROUP BY ph.UserId
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    ua.ActivityCount,
    upm.TotalQuestions,
    upm.TotalAnswers,
    COALESCE(upm.AvgQuestionScore, 0) AS AvgQuestionScore,
    COALESCE(upm.AvgAnswerScore, 0) AS AvgAnswerScore,
    aam.AcceptedAnswerCount,
    (COALESCE(aam.AcceptedAnswerCount, 0) * 1.0 / NULLIF(upm.TotalAnswers, 0)) AS AcceptanceRate,
    aam.AvgTimeToAcceptance,
    ubm.GoldBadges,
    ubm.SilverBadges,
    ubm.BronzeBadges,
    em.TotalEdits,
    (
        SELECT COUNT(*)
        FROM PostLinks pl
        JOIN Posts p_linked ON pl.PostId = p_linked.Id
        WHERE p_linked.OwnerUserId = u.Id AND pl.LinkTypeId = 3
    ) AS QuestionsMarkedAsDuplicate
FROM Users u
JOIN UserActivity ua ON u.Id = ua.UserId
LEFT JOIN UserPostMetrics upm ON u.Id = upm.OwnerUserId
LEFT JOIN UserBadgeMetrics ubm ON u.Id = ubm.UserId
LEFT JOIN AcceptedAnswerMetrics aam ON u.Id = aam.OwnerUserId
LEFT JOIN EditMetrics em ON u.Id = em.UserId
WHERE u.CreationDate < (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '2' YEAR)
GROUP BY
    u.Id,
    u.DisplayName,
    u.Reputation,
    ua.ActivityCount,
    upm.TotalQuestions,
    upm.TotalAnswers,
    upm.AvgQuestionScore,
    upm.AvgAnswerScore,
    aam.AcceptedAnswerCount,
    aam.AvgTimeToAcceptance,
    ubm.GoldBadges,
    ubm.SilverBadges,
    ubm.BronzeBadges,
    em.TotalEdits
ORDER BY u.Reputation DESC, ua.ActivityCount DESC;
WITH RankedQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title AS QuestionTitle,
        p.OwnerUserId,
        p.CreationDate AS QuestionCreationDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL
),
UserQuestionStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        SUM(CASE WHEN rq.rn = 1 THEN 1 ELSE 0 END) AS IsMostRecentQuestion,
        COUNT(DISTINCT rq.QuestionId) AS TotalQuestions,
        AVG(
            CAST(
                (EXTRACT(EPOCH FROM (rq.QuestionCreationDate - u.CreationDate)) / 86400.0)
            AS DOUBLE PRECISION)
        ) AS AvgDaysToFirstQuestion,
        MAX(rq.QuestionCreationDate) AS LastQuestionDate,
        SUM(CASE WHEN EXISTS (SELECT 1 FROM PostHistory ph WHERE ph.PostId = rq.QuestionId AND ph.PostHistoryTypeId IN (10, 11)) THEN 1 ELSE 0 END) AS TotalClosedReopenedQuestions,
        CAST(SUM(CASE WHEN p_link.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DOUBLE PRECISION) / NULLIF(COUNT(DISTINCT rq.QuestionId), 0) AS DuplicateLinkRatio
    FROM Users u
    LEFT JOIN RankedQuestions rq ON u.Id = rq.OwnerUserId
    LEFT JOIN PostLinks p_link ON rq.QuestionId = p_link.PostId
    GROUP BY u.Id, u.DisplayName, u.CreationDate
)
SELECT
    ugs.DisplayName,
    ugs.TotalQuestions,
    ugs.AvgDaysToFirstQuestion,
    ugs.LastQuestionDate,
    ugs.TotalClosedReopenedQuestions,
    ugs.DuplicateLinkRatio,
    u_badges.GoldBadges,
    u_badges.SilverBadges,
    u_badges.BronzeBadges,
    COALESCE(p_latest.QuestionTitle, 'N/A') AS LatestQuestionTitle,
    CASE
        WHEN ugs.TotalQuestions > 100 THEN 'Prolific'
        WHEN ugs.TotalQuestions > 10 THEN 'Active'
        ELSE 'Infrequent'
    END AS QuestionActivityLevel,
    CASE
        WHEN u_badges.TotalBadges IS NULL THEN 'No Badges'
        WHEN u_badges.TotalBadges > 20 THEN 'Highly Decorated'
        ELSE 'Moderately Decorated'
    END AS BadgeStatus,
    (ugs.TotalQuestions * 1.0 / NULLIF(
        CAST(
            (EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - u.CreationDate)) / 86400.0) AS DOUBLE PRECISION
        ), 0
    )) AS QuestionsPerDaySinceCreation,
    CASE
        WHEN ugs.LastQuestionDate < (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '365 days') THEN 'Inactive > 1 Year'
        WHEN ugs.LastQuestionDate < (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '90 days') THEN 'Inactive > 90 Days'
        ELSE 'Recently Active'
    END AS UserActivityStatus,
    ugs.UserId,
    u.Id AS Users_Id,
    u.CreationDate
FROM UserQuestionStats ugs
JOIN Users u ON ugs.UserId = u.Id
LEFT JOIN (
    SELECT
        UserId,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(*) AS TotalBadges
    FROM Badges
    GROUP BY UserId
) u_badges ON ugs.UserId = u_badges.UserId
LEFT JOIN RankedQuestions p_latest ON ugs.UserId = p_latest.OwnerUserId AND p_latest.rn = 1
WHERE ugs.TotalQuestions > 5 AND u.Reputation > 1000
GROUP BY
    ugs.DisplayName,
    ugs.TotalQuestions,
    ugs.AvgDaysToFirstQuestion,
    ugs.LastQuestionDate,
    ugs.TotalClosedReopenedQuestions,
    ugs.DuplicateLinkRatio,
    u_badges.GoldBadges,
    u_badges.SilverBadges,
    u_badges.BronzeBadges,
    p_latest.QuestionTitle,
    ugs.UserId,
    u.Id,
    u.CreationDate,
    u_badges.TotalBadges
ORDER BY ugs.TotalQuestions DESC, ugs.LastQuestionDate DESC;
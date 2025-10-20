-- {"query": "20056.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1576} 

WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.AboutMe,
        MIN(CASE WHEN p.PostTypeId = 1 THEN p.CreationDate ELSE NULL END) AS FirstQuestionDate,
        MAX(CASE WHEN p.PostTypeId = 2 THEN p.CreationDate ELSE NULL END) AS LastAnswerDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COALESCE(AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END), 0) AS AvgAnswerScore,
        COALESCE(SUM(p.FavoriteCount), 0) AS TotalFavoritesOnPosts,
        (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id) AS TotalCommentsMade,
        (SELECT COUNT(*) FROM PostHistory ph WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId = 10) AS PostsClosedByOthers
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    WHERE
        u.CreationDate BETWEEN '2015-01-01' AND '2023-12-31'
        AND u.Reputation > 1000
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location, u.AboutMe
),
UserBadges AS (
    SELECT
        UserId,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(CASE WHEN TagBased = '1' THEN 1 ELSE NULL END) AS TagBasedBadges
    FROM
        Badges
    GROUP BY
        UserId
),
AnswerTimeGaps AS (
    SELECT
        OwnerUserId,
        AVG(AnswerInterval) AS AvgMinutesBetweenAnswers
    FROM (
        SELECT
            OwnerUserId,
            EXTRACT(EPOCH FROM (CreationDate - LAG(CreationDate, 1) OVER (PARTITION BY OwnerUserId ORDER BY CreationDate))) / 60 AS AnswerInterval
        FROM
            Posts
        WHERE PostTypeId = 2 -- Answers
    ) AS AnswerIntervals
    WHERE
        AnswerInterval IS NOT NULL AND AnswerInterval > 0
    GROUP BY
        OwnerUserId
),
UserEngagementScore AS (
    SELECT
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        EXTRACT(YEAR FROM ua.CreationDate) AS CohortYear,
        COALESCE(ub.GoldBadges, 0) AS GoldBadges,
        COALESCE(ub.SilverBadges, 0) AS SilverBadges,
        COALESCE(ub.BronzeBadges, 0) AS BronzeBadges,
        ua.TotalQuestions,
        ua.TotalAnswers,
        ua.AvgAnswerScore,
        atg.AvgMinutesBetweenAnswers,
        CASE
            WHEN ua.AboutMe IS NULL OR LENGTH(TRIM(ua.AboutMe)) = 0 THEN 'No Bio'
            WHEN LENGTH(ua.AboutMe) > 500 THEN 'Long Bio'
            ELSE 'Short Bio'
        END AS BioStatus,
        (
            (ua.Reputation * 0.1) +
            (ua.AvgAnswerScore * 5) +
            (COALESCE(ub.GoldBadges, 0) * 100) +
            (COALESCE(ub.SilverBadges, 0) * 25) +
            (COALESCE(ub.BronzeBadges, 0) * 5) +
            (ua.TotalAnswers * 2) -
            (ua.PostsClosedByOthers * 10) +
            CASE
                WHEN ua.Location LIKE '%USA%' OR ua.Location LIKE '%United States%' THEN 50
                WHEN ua.Location LIKE '%UK%' OR ua.Location LIKE '%United Kingdom%' THEN 40
                ELSE 0
            END
        ) / NULLIF(atg.AvgMinutesBetweenAnswers, 0) AS EngagementScore
    FROM
        UserActivity ua
    LEFT JOIN
        UserBadges ub ON ua.UserId = ub.UserId
    LEFT JOIN
        AnswerTimeGaps atg ON ua.UserId = atg.OwnerUserId
),
RankedUsers AS (
    SELECT
        *,
        DENSE_RANK() OVER (PARTITION BY CohortYear ORDER BY EngagementScore DESC, Reputation DESC) AS YearlyRank
    FROM
        UserEngagementScore
    WHERE
        EngagementScore IS NOT NULL AND EngagementScore > 0
),
AskersOnly AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        EXTRACT(YEAR FROM u.CreationDate) AS CohortYear,
        u.Location,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount
    FROM
        Users u
    WHERE
        u.Reputation < 500
        AND EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1)
        AND NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2)
)
(SELECT
    'Top User' AS UserType,
    ru.DisplayName,
    ru.CohortYear,
    ru.YearlyRank,
    ru.Reputation,
    ru.EngagementScore,
    ru.GoldBadges || '/' || ru.SilverBadges || '/' || ru.BronzeBadges AS BadgeSummary,
    ru.TotalQuestions,
    ru.TotalAnswers,
    ru.BioStatus
FROM
    RankedUsers ru
WHERE
    ru.YearlyRank <= 10)
UNION ALL
(SELECT
    'Asker Only' AS UserType,
    ao.DisplayName,
    ao.CohortYear,
    NULL AS YearlyRank,
    ao.Reputation,
    NULL AS EngagementScore,
    'N/A' AS BadgeSummary,
    ao.QuestionCount AS TotalQuestions,
    0 AS TotalAnswers,
    'N/A' AS BioStatus
FROM
    AskersOnly ao
WHERE
    ao.QuestionCount > 5)
ORDER BY
    CohortYear DESC,
    UserType,
    YearlyRank ASC NULLS LAST,
    Reputation DESC;

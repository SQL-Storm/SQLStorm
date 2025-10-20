WITH UserActivity AS (
    SELECT
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.CreationDate,
        p_q.AcceptedAnswerId,
        p.Id AS PostId
    FROM Posts p
    LEFT JOIN Posts p_q ON p.ParentId = p_q.Id AND p_q.PostTypeId = 1
    WHERE p.OwnerUserId IS NOT NULL
),
UserStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS AccountCreationDate,
        MIN(ua.CreationDate) AS FirstPostDate,
        MAX(ua.CreationDate) AS LastPostDate,
        COUNT(ua.PostId) AS TotalPosts,
        COUNT(CASE WHEN ua.PostTypeId = 1 THEN 1 END) AS QuestionCount,
        COUNT(CASE WHEN ua.PostTypeId = 2 THEN 1 END) AS AnswerCount,
        SUM(CASE WHEN ua.PostTypeId = 2 AND ua.AcceptedAnswerId = ua.PostId THEN 1 ELSE 0 END) AS AcceptedAnswerCount,
        COALESCE(AVG(CASE WHEN ua.PostTypeId = 1 THEN ua.Score END), 0) AS AvgQuestionScore,
        COALESCE(AVG(CASE WHEN ua.PostTypeId = 2 THEN ua.Score END), 0) AS AvgAnswerScore,
        (EXTRACT(EPOCH FROM MAX(ua.CreationDate)) - EXTRACT(EPOCH FROM MIN(ua.CreationDate))) / 86400.0 AS PostingDaysSpan
    FROM Users u
    JOIN UserActivity ua ON u.Id = ua.OwnerUserId
    WHERE u.CreationDate < (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '3' YEAR)
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
    HAVING COUNT(CASE WHEN ua.PostTypeId = 2 THEN 1 END) > 50
),
UserBadges AS (
    SELECT
        UserId,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
),
UserEngagementScore AS (
    SELECT
        s.UserId,
        s.DisplayName,
        s.Reputation,
        s.AccountCreationDate,
        s.TotalPosts,
        s.QuestionCount,
        s.AnswerCount,
        s.AcceptedAnswerCount,
        s.AvgQuestionScore,
        s.AvgAnswerScore,
        COALESCE(b.GoldBadges, 0) AS GoldBadges,
        COALESCE(b.SilverBadges, 0) AS SilverBadges,
        COALESCE(b.BronzeBadges, 0) AS BronzeBadges,
        (
            (s.Reputation * 0.15) +
            (s.AvgAnswerScore * 10) +
            (COALESCE(b.GoldBadges, 0) * 100) +
            (COALESCE(b.SilverBadges, 0) * 25) +
            (CASE WHEN s.AnswerCount > 0 THEN (CAST(s.AcceptedAnswerCount AS DECIMAL) / s.AnswerCount) * 200 ELSE 0 END) +
            (CASE WHEN s.PostingDaysSpan > 1 THEN (s.TotalPosts / s.PostingDaysSpan) * 5 ELSE 0 END)
        ) AS EngagementScore
    FROM UserStats s
    LEFT JOIN UserBadges b ON s.UserId = b.UserId
),
RankedUsers AS (
    SELECT
        ues.UserId,
        ues.DisplayName,
        ues.Reputation,
        ues.AccountCreationDate,
        ues.TotalPosts,
        ues.QuestionCount,
        ues.AnswerCount,
        ues.AcceptedAnswerCount,
        ues.AvgQuestionScore,
        ues.AvgAnswerScore,
        ues.GoldBadges,
        ues.SilverBadges,
        ues.BronzeBadges,
        ues.EngagementScore,
        NTILE(100) OVER (ORDER BY ues.EngagementScore DESC) AS Percentile,
        CAST(NULL AS DOUBLE PRECISION) AS AvgScoreInPercentile,
        LAG(ues.DisplayName, 1, 'N/A') OVER (ORDER BY ues.EngagementScore DESC) AS UserRankedAbove,
        LEAD(ues.DisplayName, 1, 'N/A') OVER (ORDER BY ues.EngagementScore DESC) AS UserRankedBelow
    FROM UserEngagementScore ues
),
RankedUsersWithAvg AS (
    SELECT
        r.UserId,
        r.DisplayName,
        r.Reputation,
        r.AccountCreationDate,
        r.TotalPosts,
        r.QuestionCount,
        r.AnswerCount,
        r.AcceptedAnswerCount,
        r.AvgQuestionScore,
        r.AvgAnswerScore,
        r.GoldBadges,
        r.SilverBadges,
        r.BronzeBadges,
        r.EngagementScore,
        r.Percentile,
        r.UserRankedAbove,
        r.UserRankedBelow,
        agg.AvgScoreInPercentile
    FROM RankedUsers r
    JOIN (
        SELECT Percentile, AVG(EngagementScore) AS AvgScoreInPercentile
        FROM RankedUsers
        GROUP BY Percentile
    ) agg ON r.Percentile = agg.Percentile
)
SELECT
    DENSE_RANK() OVER (ORDER BY ru.EngagementScore DESC) AS Rank,
    ru.DisplayName,
    ru.Reputation,
    ru.EngagementScore,
    ru.Percentile,
    ru.AvgScoreInPercentile,
    ru.AnswerCount,
    (CASE WHEN ru.AnswerCount > 0 THEN CAST(ru.AcceptedAnswerCount AS DECIMAL) / ru.AnswerCount ELSE 0 END) AS AcceptanceRate,
    ru.AvgAnswerScore,
    ru.GoldBadges,
    ru.SilverBadges,
    ru.BronzeBadges,
    ru.AccountCreationDate,
    ru.UserRankedAbove,
    ru.UserRankedBelow
FROM RankedUsersWithAvg ru
WHERE ru.Percentile <= 5
ORDER BY Rank
LIMIT 200;
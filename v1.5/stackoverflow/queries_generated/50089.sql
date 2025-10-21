-- {"query": "50089.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1169} 

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
        SUM(CASE WHEN ua.PostTypeId = 2 THEN 1 ELSE 0 END) FILTER (WHERE ua.AcceptedAnswerId = ua.PostId) AS AcceptedAnswerCount,
        COALESCE(AVG(ua.Score) FILTER (WHERE ua.PostTypeId = 1), 0) AS AvgQuestionScore,
        COALESCE(AVG(ua.Score) FILTER (WHERE ua.PostTypeId = 2), 0) AS AvgAnswerScore,
        (EXTRACT(EPOCH FROM MAX(ua.CreationDate)) - EXTRACT(EPOCH FROM MIN(ua.CreationDate))) / 86400.0 AS PostingDaysSpan
    FROM Users u
    JOIN UserActivity ua ON u.Id = ua.OwnerUserId
    WHERE u.CreationDate < (NOW() - INTERVAL '3 year')
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
    HAVING COUNT(CASE WHEN ua.PostTypeId = 2 THEN 1 END) > 50
),
UserBadges AS (
    SELECT
        UserId,
        COUNT(*) FILTER (WHERE Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE Class = 3) AS BronzeBadges
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
            (CASE WHEN s.AnswerCount > 0 THEN (s.AcceptedAnswerCount::decimal / s.AnswerCount) * 200 ELSE 0 END) +
            (CASE WHEN s.PostingDaysSpan > 1 THEN s.TotalPosts / s.PostingDaysSpan ELSE 0 END * 5)
        ) AS EngagementScore
    FROM UserStats s
    LEFT JOIN UserBadges b ON s.UserId = b.UserId
),
RankedUsers AS (
    SELECT
        *,
        NTILE(100) OVER (ORDER BY EngagementScore DESC) AS Percentile,
        AVG(EngagementScore) OVER (PARTITION BY NTILE(100) OVER (ORDER BY EngagementScore DESC)) AS AvgScoreInPercentile,
        LAG(DisplayName, 1, 'N/A') OVER (ORDER BY EngagementScore DESC) AS UserRankedAbove,
        LEAD(DisplayName, 1, 'N/A') OVER (ORDER BY EngagementScore DESC) AS UserRankedBelow
    FROM UserEngagementScore
)
SELECT
    DENSE_RANK() OVER (ORDER BY ru.EngagementScore DESC) AS Rank,
    ru.DisplayName,
    ru.Reputation,
    ru.EngagementScore,
    ru.Percentile,
    ru.AvgScoreInPercentile,
    ru.AnswerCount,
    (CASE WHEN ru.AnswerCount > 0 THEN ru.AcceptedAnswerCount::decimal / ru.AnswerCount ELSE 0 END) AS AcceptanceRate,
    ru.AvgAnswerScore,
    ru.GoldBadges,
    ru.SilverBadges,
    ru.BronzeBadges,
    ru.AccountCreationDate,
    ru.UserRankedAbove,
    ru.UserRankedBelow
FROM RankedUsers ru
WHERE ru.Percentile <= 5 -- Top 5%
ORDER BY Rank
LIMIT 200;

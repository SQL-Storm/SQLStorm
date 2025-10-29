-- {"query": "4563.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 998} 

WITH UserPostStats AS (
    SELECT
        p.OwnerUserId,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(p.Score) AS AvgScore,
        MAX(p.CreationDate) AS LatestPostDate
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserBadgeCounts AS (
    SELECT
        UserId,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
),
PostActivity AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.Score,
        COUNT(c.Id) AS CommentCount,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (5, 8) THEN 1 ELSE 0 END) AS BodyEditCount,
        ROW_NUMBER() OVER(PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) as ActivityRank
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (2, 5, 8) -- Initial Body, Edit Body, Rollback Body
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.Id, p.OwnerUserId, p.Title, p.CreationDate, p.Score
),
UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(ups.TotalPosts, 0) AS TotalPosts,
        COALESCE(ups.QuestionCount, 0) AS TotalQuestions,
        COALESCE(ups.AnswerCount, 0) AS TotalAnswers,
        COALESCE(ubc.GoldBadges, 0) AS GoldBadges,
        COALESCE(ubc.SilverBadges, 0) AS SilverBadges,
        COALESCE(ubc.BronzeBadges, 0) AS BronzeBadges,
        CASE
            WHEN ups.AvgScore > 50 THEN 'High Performer'
            WHEN ups.AvgScore > 10 THEN 'Solid Contributor'
            ELSE 'Emerging'
        END AS PerformanceTier,
        DATEDIFF(day, u.CreationDate, GETDATE()) AS DaysSinceCreation,
        CASE
            WHEN u.LastAccessDate < DATEADD(month, -6, GETDATE()) THEN 'Inactive'
            ELSE 'Active'
        END AS UserStatus
    FROM Users u
    LEFT JOIN UserPostStats ups ON u.Id = ups.OwnerUserId
    LEFT JOIN UserBadgeCounts ubc ON u.Id = ubc.UserId
    WHERE u.Id > 0 -- Exclude potential system users or invalid IDs
)
SELECT
    ue.UserId,
    ue.DisplayName,
    ue.Reputation,
    ue.TotalPosts,
    ue.TotalQuestions,
    ue.TotalAnswers,
    ue.GoldBadges,
    ue.SilverBadges,
    ue.BronzeBadges,
    ue.PerformanceTier,
    ue.UserStatus,
    pa.Title AS LatestActivityTitle,
    pa.Score AS LatestActivityScore,
    pa.CommentCount AS LatestActivityCommentCount,
    pa.BodyEditCount AS LatestActivityBodyEdits,
    CONCAT(ue.DisplayName, ' has ', ue.Reputation, ' reputation and has posted ', ue.TotalPosts, ' posts. Their status is ', ue.UserStatus, '.') AS UserSummaryString
FROM UserEngagement ue
LEFT JOIN PostActivity pa ON ue.UserId = pa.OwnerUserId AND pa.ActivityRank = 1
WHERE ue.Reputation > 1000
AND ue.TotalPosts > 5
AND ue.DaysSinceCreation > 30
ORDER BY ue.Reputation DESC, ue.TotalPosts DESC
LIMIT 100;

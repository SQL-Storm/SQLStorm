-- {"query": "13061.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2142, "output_tokens": 837} 
WITH UserActivity AS (
    SELECT 
        OwnerUserId,
        COUNT(DISTINCT CASE WHEN PostTypeId = 1 THEN Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN PostTypeId = 2 THEN Id END) AS AnswersProvided,
        SUM(CASE WHEN PostTypeId IN (1, 2) THEN Score ELSE 0 END) AS TotalScore,
        AVG(CASE WHEN PostTypeId IN (1, 2) THEN ViewCount ELSE NULL END) AS AvgViewCount,
        MAX(CreationDate) AS LastActivityDate
    FROM Posts
    WHERE OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
),
TopContributors AS (
    SELECT 
        OwnerUserId,
        QuestionsAsked,
        AnswersProvided,
        TotalScore,
        AvgViewCount,
        LastActivityDate,
        ROW_NUMBER() OVER (ORDER BY TotalScore DESC, QuestionsAsked DESC, AnswersProvided DESC) AS Rank
    FROM UserActivity
),
BadgeSummary AS (
    SELECT
        UserId,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
),
UserPerformance AS (
    SELECT
        tc.OwnerUserId,
        u.DisplayName,
        tc.QuestionsAsked,
        tc.AnswersProvided,
        tc.TotalScore,
        tc.AvgViewCount,
        tc.LastActivityDate,
        bs.GoldBadges,
        bs.SilverBadges,
        bs.BronzeBadges,
        SUM(CASE WHEN ph.PostHistoryTypeId = 5 THEN 1 ELSE 0 END) AS EditsMade,
        COUNT(DISTINCT ph.PostId) AS UniquePostsEdited
    FROM TopContributors tc
    JOIN Users u ON tc.OwnerUserId = u.Id
    LEFT JOIN BadgeSummary bs ON tc.OwnerUserId = bs.UserId
    LEFT JOIN PostHistory ph ON tc.OwnerUserId = ph.UserId AND ph.PostHistoryTypeId = 5
    WHERE tc.Rank <= 100
    GROUP BY tc.OwnerUserId, u.DisplayName, tc.QuestionsAsked, tc.AnswersProvided, tc.TotalScore, tc.AvgViewCount, tc.LastActivityDate, bs.GoldBadges, bs.SilverBadges, bs.BronzeBadges
)
SELECT 
    up.OwnerUserId,
    up.DisplayName,
    up.QuestionsAsked,
    up.AnswersProvided,
    up.TotalScore,
    COALESCE(up.AvgViewCount, 0) AS AvgViewCount,
    up.LastActivityDate,
    up.GoldBadges,
    up.SilverBadges,
    up.BronzeBadges,
    up.EditsMade,
    up.UniquePostsEdited,
    CONCAT(up.DisplayName, ' has edited ', up.EditsMade, ' times and is ranked #', tc.Rank) AS UserSummary
FROM UserPerformance up
JOIN TopContributors tc ON up.OwnerUserId = tc.OwnerUserId
WHERE EXISTS (
    SELECT 1
    FROM Posts p
    WHERE p.OwnerUserId = up.OwnerUserId
      AND p.CreationDate > DATE_TRUNC('month', cast('2024-10-01' as date)) - INTERVAL '6 months'
)
ORDER BY up.TotalScore DESC, up.QuestionsAsked DESC, up.AnswersProvided DESC;
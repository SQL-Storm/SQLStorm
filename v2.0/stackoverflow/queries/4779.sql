-- {"query": "4779.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1353} 
WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.CreationDate,
        pht.Name AS PostHistoryTypeName,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
),
UserPostInteraction AS (
    SELECT
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
    GROUP BY p.OwnerUserId
),
HighReputationUsers AS (
    SELECT
        u.Id
    FROM Users u
    WHERE u.Reputation > 10000
),
UserBadgeCounts AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
TagPopularity AS (
    SELECT
        t.TagName,
        t.Count AS TagUsageCount,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS PopularityRank
    FROM Tags t
    WHERE t.Count > 1000
),
RecentHighScoreAnswers AS (
    SELECT
        p.ParentId AS QuestionId,
        COUNT(p.Id) AS RecentAnswerCount,
        SUM(p.Score) AS TotalScoreOfRecentAnswers,
        MAX(p.CreationDate) AS LastAnswerDate
    FROM Posts p
    WHERE p.PostTypeId = 2
      AND p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days'
      AND p.Score > 5
    GROUP BY p.ParentId
    HAVING COUNT(p.Id) >= 2
),
UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views AS UserViews,
        COALESCE(up.TotalPostsOwned, 0) AS TotalOwned,
        COALESCE(up.QuestionCount, 0) AS TotalQuestions,
        COALESCE(up.AnswerCount, 0) AS TotalAnswers,
        COALESCE(up.AvgPostScore, 0) AS AveragePostScore,
        COALESCE(ubc.GoldBadges, 0) AS GoldBadges,
        COALESCE(ubc.SilverBadges, 0) AS SilverBadges,
        COALESCE(ubc.BronzeBadges, 0) AS BronzeBadges,
        CASE
            WHEN u.LastAccessDate < cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year' THEN 'Inactive'
            WHEN u.LastAccessDate < cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '3 months' THEN 'Moderately Active'
            ELSE 'Active'
        END AS ActivityStatus,
        LOWER(SUBSTRING(u.DisplayName FROM 1 FOR 1)) AS FirstInitial,
        CASE WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl <> '' THEN 1 ELSE 0 END AS HasWebsite
    FROM Users u
    LEFT JOIN UserPostInteraction up ON u.Id = up.OwnerUserId
    LEFT JOIN UserBadgeCounts ubc ON u.Id = ubc.UserId
)
SELECT
    uas.DisplayName,
    uas.Reputation,
    uas.TotalOwned,
    uas.TotalQuestions,
    uas.TotalAnswers,
    uas.AveragePostScore,
    uas.GoldBadges,
    uas.SilverBadges,
    uas.BronzeBadges,
    uas.ActivityStatus,
    uas.FirstInitial,
    uas.HasWebsite,
    COALESCE(rha.RecentAnswerCount, 0) AS RecentHighScoreAnswerCount,
    COALESCE(rha.TotalScoreOfRecentAnswers, 0) AS TotalScoreOfRecentAnswers,
    CASE
        WHEN uas.Reputation BETWEEN 1 AND 100 THEN 'Novice'
        WHEN uas.Reputation BETWEEN 101 AND 1000 THEN 'Beginner'
        WHEN uas.Reputation BETWEEN 1001 AND 10000 THEN 'Intermediate'
        WHEN uas.Reputation > 10000 THEN 'Expert'
        ELSE 'Unranked'
    END AS ReputationLevel,
    tp.TagName AS TopTag,
    tp.TagUsageCount AS TopTagUsage,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = uas.UserId AND p2.ClosedDate IS NOT NULL) AS ClosedPostsOwned,
    (SELECT MAX(rpe.CreationDate) FROM RankedPostEdits rpe WHERE rpe.UserId = uas.UserId AND rpe.rn = 1) AS LastEditDateByThisUser
FROM UserActivitySummary uas
LEFT JOIN RecentHighScoreAnswers rha ON uas.UserId = rha.QuestionId
LEFT JOIN TagPopularity tp ON tp.PopularityRank = (uas.TotalQuestions % 5) + 1 -- Arbitrary link to tag popularity
WHERE uas.Reputation > 50
ORDER BY uas.Reputation DESC, uas.TotalAnswers DESC
LIMIT 100;
-- {"query": "4351.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1528}
WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        ROW_NUMBER() OVER(PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) AND p.OwnerUserId IS NOT NULL
),
UserPostStats AS (
    SELECT
        rp.OwnerUserId,
        COUNT(CASE WHEN rp.PostTypeId = 1 THEN rp.PostId END) AS QuestionCount,
        COUNT(CASE WHEN rp.PostTypeId = 2 THEN rp.PostId END) AS AnswerCount,
        SUM(CASE WHEN rp.PostTypeId = 1 THEN rp.PostScore ELSE 0 END) AS TotalQuestionScore,
        SUM(CASE WHEN rp.PostTypeId = 2 THEN rp.PostScore ELSE 0 END) AS TotalAnswerScore,
        AVG(CASE WHEN rp.PostTypeId = 1 THEN rp.PostViewCount ELSE NULL END) AS AvgQuestionViewCount,
        MAX(CASE WHEN rp.rn = 1 THEN rp.PostCreationDate ELSE NULL END) AS LastPostDate,
        MAX(CASE WHEN rp.rn = 1 THEN rp.PostScore ELSE NULL END) AS ScoreOfLastPost
    FROM RankedPosts rp
    WHERE rp.rn <= 5
    GROUP BY rp.OwnerUserId
),
UserBadgeCounts AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadgeCount,
        COUNT(CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadgeCount,
        COUNT(CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadgeCount
    FROM Badges b
    GROUP BY b.UserId
),
UserPostLinkCounts AS (
    SELECT
        pl.PostId,
        COUNT(pl.Id) AS PostLinkCount
    FROM PostLinks pl
    GROUP BY pl.PostId
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.Views AS UserTotalViews,
    COALESCE(ups.QuestionCount, 0) AS TotalQuestions,
    COALESCE(ups.AnswerCount, 0) AS TotalAnswers,
    COALESCE(ups.TotalQuestionScore, 0) AS TotalQuestionScore,
    COALESCE(ups.TotalAnswerScore, 0) AS TotalAnswerScore,
    COALESCE(ups.AvgQuestionViewCount, 0) AS AverageQuestionViews,
    COALESCE(ubc.GoldBadgeCount, 0) AS GoldBadges,
    COALESCE(ubc.SilverBadgeCount, 0) AS SilverBadges,
    COALESCE(ubc.BronzeBadgeCount, 0) AS BronzeBadges,
    CASE
        WHEN ups.LastPostDate IS NULL THEN 'Never Posted'
        WHEN ups.LastPostDate > (cast('2024-10-01' as date) - INTERVAL '30 day') THEN 'Recent'
        WHEN ups.LastPostDate > (cast('2024-10-01' as date) - INTERVAL '365 day') THEN 'ActiveWithinYear'
        ELSE 'Inactive'
    END AS UserActivityLevel,
    COALESCE(uplc.PostLinkCount, 0) AS PostsLinkedTo,
    (u.UpVotes - u.DownVotes) AS NetVotes,
    CASE WHEN u.WebsiteUrl IS NULL THEN 'No Website' ELSE 'Has Website' END AS HasWebsiteIndicator,
    CASE WHEN u.AboutMe LIKE '%SQL%' THEN 'SQL Enthusiast' WHEN u.AboutMe LIKE '%Database%' THEN 'Database Focused' ELSE 'General Bio' END AS AboutMeFocus,
    CASE
        WHEN u.Reputation >= 100000 THEN 'HighReputation'
        WHEN u.Reputation >= 10000 THEN 'MidReputation'
        ELSE 'LowReputation'
    END AS ReputationTier,
    CAST(EXTRACT(YEAR FROM u.CreationDate) AS INTEGER) AS UserCreationYear,
    LPAD(CAST(EXTRACT(HOUR FROM u.CreationDate) AS VARCHAR), 2, '0') AS UserCreationHour,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id AND c.Score > 5) AS HighScoringComments,
    COALESCE(ups.ScoreOfLastPost, 0) AS ScoreOfMostRecentPost,
    COALESCE((CAST(u.LastAccessDate AS DATE) = CAST(u.CreationDate AS DATE)), FALSE) AS IsFirstAccessOnCreation,
    CASE WHEN u.AccountId IS NULL THEN 'No AccountId' ELSE 'Has AccountId' END AS AccountIdStatus
FROM Users u
LEFT JOIN UserPostStats ups ON u.Id = ups.OwnerUserId
LEFT JOIN UserBadgeCounts ubc ON u.Id = ubc.UserId
LEFT JOIN UserPostLinkCounts uplc ON u.Id = uplc.PostId
WHERE u.Id > 10000 AND u.Reputation BETWEEN 500 AND 50000

UNION

SELECT
    -1 AS UserId,
    'Community User' AS DisplayName,
    -1 AS Reputation,
    CAST('1970-01-01' AS timestamp) AS UserCreationDate,
    -1 AS UserTotalViews,
    COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
    COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalQuestionScore,
    SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
    AVG(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE NULL END) AS AverageQuestionViews,
    0 AS GoldBadges,
    0 AS SilverBadges,
    0 AS BronzeBadges,
    'Community' AS UserActivityLevel,
    0 AS PostsLinkedTo,
    0 AS NetVotes,
    'No Website' AS HasWebsiteIndicator,
    'General Bio' AS AboutMeFocus,
    'CommunityReputation' AS ReputationTier,
    0 AS UserCreationYear,
    '00' AS UserCreationHour,
    0 AS HighScoringComments,
    0 AS ScoreOfMostRecentPost,
    FALSE AS IsFirstAccessOnCreation,
    'No AccountId' AS AccountIdStatus
FROM Posts p
WHERE p.OwnerUserId = -1
GROUP BY p.PostTypeId
ORDER BY UserId;
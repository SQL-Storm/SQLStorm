-- {"query": "7186.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2461} 
WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        MAX(p.CreationDate) AS LastPostDate,
        AVG(p.Score) AS AvgPostScore,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') AS AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2010-01-01' AND u.CreationDate < '2023-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        PostCount,
        CommentCount,
        BadgeCount,
        QuestionCount,
        AnswerCount,
        LastPostDate,
        AvgPostScore,
        AllTags,
        DENSE_RANK() OVER (ORDER BY Reputation DESC, PostCount DESC) AS RankByReputation,
        ROW_NUMBER() OVER (ORDER BY PostCount DESC, Reputation DESC) AS RankByPostCount
    FROM UserStats
),
BadgesByType AS (
    SELECT 
        b.UserId,
        b.Name,
        b.Date,
        b.Class,
        CASE 
            WHEN b.Class = 1 THEN 'Gold'
            WHEN b.Class = 2 THEN 'Silver'
            ELSE 'Bronze'
        END AS BadgeType,
        COUNT(*) OVER (PARTITION BY b.UserId, b.Class) AS CountPerClass,
        LAG(b.Date) OVER (PARTITION BY b.UserId ORDER BY b.Date) AS PreviousBadgeDate,
        DATEDIFF(DAY, LAG(b.Date) OVER (PARTITION BY b.UserId ORDER BY b.Date), b.Date) AS DaysBetweenBadges
    FROM Badges b
    WHERE b.Date >= '2015-01-01' AND b.Date < '2023-01-01'
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS Questions,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS Answers,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 3 THEN 1 ELSE 0 END), 0) AS Wikis,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        MAX(p.CreationDate) AS LastActivity,
        MIN(p.CreationDate) AS FirstPost,
        DATEDIFF(DAY, MIN(p.CreationDate), MAX(p.CreationDate)) AS ActiveDays,
        RANK() OVER (ORDER BY COALESCE(SUM(p.Score), 0) DESC) AS ScoreRank,
        CASE 
            WHEN COUNT(DISTINCT p.Id) = 0 THEN 0
            ELSE COALESCE(SUM(p.Score), 0) / COUNT(DISTINCT p.Id)
        END AS AvgScorePerPost
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.CreationDate >= '2015-01-01' OR p.CreationDate IS NULL
    GROUP BY u.Id, u.DisplayName
),
ComplexAnalysis AS (
    SELECT 
        tu.UserId,
        tu.DisplayName,
        tu.Reputation,
        tu.PostCount,
        tu.CommentCount,
        tu.BadgeCount,
        tu.QuestionCount,
        tu.AnswerCount,
        tu.LastPostDate,
        tu.AvgPostScore,
        tu.AllTags,
        tu.RankByReputation,
        tu.RankByPostCount,
        ba.BadgeType,
        ba.CountPerClass,
        ba.DaysBetweenBadges,
        ua.Questions,
        ua.Answers,
        ua.Wikis,
        ua.TotalPosts,
        ua.LastActivity,
        ua.FirstPost,
        ua.ActiveDays,
        ua.ScoreRank,
        ua.AvgScorePerPost,
        CASE 
            WHEN tu.PostCount > 100 AND tu.Reputation > 10000 THEN 'Elite'
            WHEN tu.PostCount > 50 AND tu.Reputation > 5000 THEN 'Veteran'
            WHEN tu.PostCount > 10 THEN 'Active'
            ELSE 'Regular'
        END AS UserCategory,
        CASE 
            WHEN tu.BadgeCount > 50 THEN 'AwardWinner'
            WHEN tu.BadgeCount > 20 THEN 'Achiever'
            WHEN tu.BadgeCount > 5 THEN 'Contributor'
            ELSE 'Participant'
        END AS BadgeLevel,
        ROW_NUMBER() OVER (PARTITION BY tu.BadgeType ORDER BY tu.Reputation DESC) AS BadgeRankByType,
        PERCENT_RANK() OVER (ORDER BY tu.Reputation) AS ReputationPercentile,
        NTILE(10) OVER (ORDER BY tu.PostCount) AS PostCountDecile
    FROM TopUsers tu
    LEFT JOIN BadgesByType ba ON tu.UserId = ba.UserId
    LEFT JOIN UserActivity ua ON tu.UserId = ua.UserId
),
FilteredAnalysis AS (
    SELECT 
        ca.UserId,
        ca.DisplayName,
        ca.Reputation,
        ca.PostCount,
        ca.CommentCount,
        ca.BadgeCount,
        ca.QuestionCount,
        ca.AnswerCount,
        ca.LastPostDate,
        ca.AvgPostScore,
        ca.AllTags,
        ca.RankByReputation,
        ca.RankByPostCount,
        ca.BadgeType,
        ca.CountPerClass,
        ca.DaysBetweenBadges,
        ca.Questions,
        ca.Answers,
        ca.Wikis,
        ca.TotalPosts,
        ca.LastActivity,
        ca.FirstPost,
        ca.ActiveDays,
        ca.ScoreRank,
        ca.AvgScorePerPost,
        ca.UserCategory,
        ca.BadgeLevel,
        ca.BadgeRankByType,
        ca.ReputationPercentile,
        ca.PostCountDecile,
        CASE 
            WHEN ca.PostCount > 0 AND ca.BadgeCount > 0 THEN 'Engaged'
            WHEN ca.PostCount > 0 THEN 'Active'
            WHEN ca.BadgeCount > 0 THEN 'Recognized'
            ELSE 'Inactive'
        END AS EngagementStatus,
        CASE 
            WHEN ca.Reputation > 50000 THEN 'HallOfFame'
            WHEN ca.Reputation > 10000 THEN 'HighReputation'
            WHEN ca.Reputation > 1000 THEN 'ModerateReputation'
            ELSE 'LowReputation'
        END AS ReputationTier
    FROM ComplexAnalysis ca
    WHERE (ca.UserCategory = 'Elite' OR ca.BadgeLevel = 'AwardWinner')
      AND (ca.ActiveDays > 365 OR ca.TotalPosts > 50)
),
FinalResults AS (
    SELECT 
        fa.UserId,
        fa.DisplayName,
        fa.Reputation,
        fa.PostCount,
        fa.CommentCount,
        fa.BadgeCount,
        fa.QuestionCount,
        fa.AnswerCount,
        fa.LastPostDate,
        fa.AvgPostScore,
        fa.AllTags,
        fa.RankByReputation,
        fa.RankByPostCount,
        fa.BadgeType,
        fa.CountPerClass,
        fa.DaysBetweenBadges,
        fa.Questions,
        fa.Answers,
        fa.Wikis,
        fa.TotalPosts,
        fa.LastActivity,
        fa.FirstPost,
        fa.ActiveDays,
        fa.ScoreRank,
        fa.AvgScorePerPost,
        fa.UserCategory,
        fa.BadgeLevel,
        fa.BadgeRankByType,
        fa.ReputationPercentile,
        fa.PostCountDecile,
        fa.EngagementStatus,
        fa.ReputationTier,
        ROW_NUMBER() OVER (ORDER BY fa.Reputation DESC, fa.PostCount DESC, fa.BadgeCount DESC) AS GlobalRank,
        RANK() OVER (PARTITION BY fa.ReputationTier ORDER BY fa.PostCount DESC) AS TierRank,
        DENSE_RANK() OVER (ORDER BY fa.LastActivity DESC) AS RecentActivityRank
    FROM FilteredAnalysis fa
)
SELECT 
    fr.GlobalRank,
    fr.UserId,
    fr.DisplayName,
    fr.Reputation,
    fr.PostCount,
    fr.CommentCount,
    fr.BadgeCount,
    fr.QuestionCount,
    fr.AnswerCount,
    fr.LastPostDate,
    fr.AvgPostScore,
    CASE 
        WHEN fr.AllTags IS NOT NULL THEN LEFT(fr.AllTags, 100)
        ELSE 'No tags'
    END AS SampleTags,
    fr.RankByReputation,
    fr.RankByPostCount,
    CASE 
        WHEN fr.BadgeType IS NOT NULL THEN fr.BadgeType
        ELSE 'No badges'
    END AS UserBadgeType,
    CASE 
        WHEN fr.CountPerClass > 0 THEN fr.CountPerClass
        ELSE 0
    END AS BadgeCountByType,
    CASE 
        WHEN fr.DaysBetweenBadges IS NOT NULL THEN fr.DaysBetweenBadges
        ELSE 0
    END AS DaysBetweenRecentBadges,
    fr.Questions,
    fr.Answers,
    fr.Wikis,
    fr.TotalPosts,
    fr.LastActivity,
    fr.FirstPost,
    fr.ActiveDays,
    fr.ScoreRank,
    fr.AvgScorePerPost,
    CASE 
        WHEN fr.UserCategory IS NOT NULL THEN fr.UserCategory
        ELSE 'Undefined'
    END AS UserCategoryDescription,
    CASE 
        WHEN fr.BadgeLevel IS NOT NULL THEN fr.BadgeLevel
        ELSE 'None'
    END AS BadgeLevelDescription,
    CASE 
        WHEN fr.BadgeRankByType > 0 THEN fr.BadgeRankByType
        ELSE 0
    END AS BadgeRankByTypeValue,
    CASE 
        WHEN fr.ReputationPercentile IS NOT NULL THEN ROUND(fr.ReputationPercentile * 100, 2)
        ELSE 0
    END AS ReputationPercentileValue,
    CASE 
        WHEN fr.PostCountDecile > 0 THEN fr.PostCountDecile
        ELSE 0
    END AS PostCountDecileValue,
    CASE 
        WHEN fr.EngagementStatus IS NOT NULL THEN fr.EngagementStatus
        ELSE 'Unknown'
    END AS EngagementStatusValue,
    CASE 
        WHEN fr.ReputationTier IS NOT NULL THEN fr.ReputationTier
        ELSE 'Unknown'
    END AS ReputationTierValue
FROM FinalResults fr
WHERE fr.GlobalRank <= 1000
  AND (fr.Reputation > 1000 OR fr.BadgeCount > 10 OR fr.PostCount > 50)
  AND fr.LastActivity >= '2022-01-01'
  AND fr.FirstPost >= '2010-01-01'
ORDER BY fr.Reputation DESC, fr.PostCount DESC, fr.BadgeCount DESC
LIMIT 1000;
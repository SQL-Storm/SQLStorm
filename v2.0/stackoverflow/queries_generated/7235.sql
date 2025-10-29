-- {"query": "7235.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2145} 
WITH UserStats AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.DisplayName,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT b.Id) as BadgeCount,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        MAX(p.CreationDate) as LastPostDate,
        CASE 
            WHEN u.Reputation >= 10000 THEN 'Elite'
            WHEN u.Reputation >= 1000 THEN 'Professional'
            WHEN u.Reputation >= 100 THEN 'Novice'
            ELSE 'Beginner'
        END as ReputationTier,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END), 0) as QuestionCount,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END), 0) as AnswerCount,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        RANK() OVER (ORDER BY SUM(p.Score) DESC) as ScoreRank,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT b.Id) DESC) as BadgeRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes
),
TopUsers AS (
    SELECT 
        UserId,
        Reputation,
        DisplayName,
        PostCount,
        BadgeCount,
        QuestionCount,
        AnswerCount,
        TotalScore,
        ScoreRank,
        BadgeRank,
        ROW_NUMBER() OVER (ORDER BY TotalScore DESC) as RankByScore,
        ROW_NUMBER() OVER (ORDER BY BadgeCount DESC) as RankByBadges
    FROM UserStats
    WHERE PostCount > 0
),
TagUsage AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        AVG(p.Score) as AvgScore,
        COUNT(DISTINCT p.OwnerUserId) as UserCount,
        STRING_AGG(DISTINCT u.DisplayName, ', ') as TagUsers,
        RANK() OVER (ORDER BY SUM(p.Score) DESC) as ScoreRank,
        PERCENT_RANK() OVER (ORDER BY t.Count) as PercentileRank
    FROM Tags t
    LEFT JOIN Posts p ON STRING_TO_ARRAY(p.Tags, '><') @> ARRAY[t.TagName]
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE t.Count > 10
    GROUP BY t.TagName, t.Count
),
ComplexAnalytics AS (
    SELECT 
        tu.UserId,
        tu.DisplayName,
        tu.Reputation,
        tu.PostCount,
        tu.BadgeCount,
        tu.QuestionCount,
        tu.AnswerCount,
        tu.TotalScore,
        tu.ScoreRank,
        tu.BadgeRank,
        tu.RankByScore,
        tu.RankByBadges,
        CASE WHEN tu.BadgeCount > 50 THEN 'Master' 
             WHEN tu.BadgeCount > 25 THEN 'Expert' 
             ELSE 'Enthusiast' END as BadgeLevel,
        CASE WHEN tu.QuestionCount > 50 THEN 'Active Questioner' 
             WHEN tu.QuestionCount > 10 THEN 'Regular Questioner' 
             ELSE 'Occasional Questioner' END as QuestionActivity,
        CASE WHEN tu.AnswerCount > 200 THEN 'Veteran Answerer' 
             WHEN tu.AnswerCount > 50 THEN 'Regular Answerer' 
             ELSE 'Occasional Answerer' END as AnswerActivity,
        DATEDIFF(day, tu.LastPostDate, CURRENT_TIMESTAMP) as DaysSinceLastPost,
        (tu.TotalScore * 1.0 / NULLIF(tu.Reputation, 0)) as ScorePerReputation,
        ABS(tu.PostCount - LAG(tu.PostCount) OVER (ORDER BY tu.PostCount)) as PostCountChange,
        ROW_NUMBER() OVER (PARTITION BY tu.BadgeLevel ORDER BY tu.TotalScore DESC) as WithinBadgeLevelRank
    FROM TopUsers tu
),
PostBreakdown AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.LastActivityDate,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question' 
            WHEN p.PostTypeId = 2 THEN 'Answer' 
            ELSE 'Other' 
        END as PostType,
        COALESCE(p.Score, 0) / NULLIF(p.ViewCount, 0) as ScoreRatio,
        CASE WHEN p.AnswerCount > 0 THEN 'Has Answers' ELSE 'No Answers' END as AnswerStatus,
        CASE 
            WHEN p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'Above Avg'
            WHEN p.Score < (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'Below Avg'
            ELSE 'Avg' 
        END as ScoreCategory,
        CASE 
            WHEN p.CreationDate > (SELECT MAX(CreationDate) - INTERVAL '30 days' FROM Posts) THEN 'Recent'
            WHEN p.CreationDate > (SELECT MAX(CreationDate) - INTERVAL '90 days' FROM Posts) THEN 'Medium'
            ELSE 'Old' 
        END as Recency,
        DATEDIFF(day, p.CreationDate, CURRENT_TIMESTAMP) as AgeInDays,
        DENSE_RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) as ScoreRankByType,
        RANK() OVER (ORDER BY p.CreationDate) as ChronologicalRank
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
FinalAnalysis AS (
    SELECT 
        ca.UserId,
        ca.DisplayName,
        ca.Reputation,
        ca.PostCount,
        ca.BadgeCount,
        ca.QuestionCount,
        ca.AnswerCount,
        ca.TotalScore,
        ca.ScoreRank,
        ca.BadgeRank,
        ca.RankByScore,
        ca.RankByBadges,
        ca.BadgeLevel,
        ca.QuestionActivity,
        ca.AnswerActivity,
        ca.DaysSinceLastPost,
        ca.ScorePerReputation,
        ca.WithinBadgeLevelRank,
        tb.ScoreRatio,
        tb.AnswerStatus,
        tb.ScoreCategory,
        tb.Recency,
        tb.AgeInDays,
        tb.ScoreRankByType,
        tb.ChronologicalRank,
        CASE 
            WHEN ca.QuestionCount > 0 AND ca.AnswerCount > 0 THEN 'Active Contributor'
            WHEN ca.QuestionCount > 0 THEN 'Questioner'
            WHEN ca.AnswerCount > 0 THEN 'Answerer'
            ELSE 'Observer'
        END as EngagementLevel,
        CASE 
            WHEN ca.BadgeCount >= 100 THEN 'Legend'
            WHEN ca.BadgeCount >= 50 THEN 'Veteran'
            WHEN ca.BadgeCount >= 25 THEN 'Active'
            ELSE 'Contributor'
        END as ContributionTier,
        CASE 
            WHEN tb.ScoreRatio > 1.0 THEN 'High Activity'
            WHEN tb.ScoreRatio > 0.5 THEN 'Medium Activity'
            ELSE 'Low Activity'
        END as ActivityLevel,
        COALESCE(
            (SELECT COUNT(*) 
             FROM Comments c 
             WHERE c.UserId = ca.UserId 
             AND c.CreationDate > (SELECT MAX(CreationDate) - INTERVAL '30 days' FROM Comments)
            ), 0) as RecentComments
    FROM ComplexAnalytics ca
    LEFT JOIN PostBreakdown tb ON ca.UserId = tb.OwnerUserId
    WHERE tb.ScoreRankByType <= 10 OR tb.ScoreRankByType IS NULL
)
SELECT 
    fa.UserId,
    fa.DisplayName,
    fa.Reputation,
    fa.PostCount,
    fa.BadgeCount,
    fa.QuestionCount,
    fa.AnswerCount,
    fa.TotalScore,
    fa.ScoreRank,
    fa.BadgeRank,
    fa.RankByScore,
    fa.RankByBadges,
    fa.BadgeLevel,
    fa.QuestionActivity,
    fa.AnswerActivity,
    fa.DaysSinceLastPost,
    fa.ScorePerReputation,
    fa.WithinBadgeLevelRank,
    fa.ScoreRatio,
    fa.AnswerStatus,
    fa.ScoreCategory,
    fa.Recency,
    fa.AgeInDays,
    fa.ScoreRankByType,
    fa.ChronologicalRank,
    fa.EngagementLevel,
    fa.ContributionTier,
    fa.ActivityLevel,
    fa.RecentComments,
    ROW_NUMBER() OVER (ORDER BY fa.TotalScore DESC, fa.BadgeCount DESC) as OverallRank,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY fa.TotalScore) as MedianScore,
    AVG(fa.ScorePerReputation) OVER (PARTITION BY fa.ContributionTier) as AvgScorePerRepByTier,
    COUNT(*) OVER () as TotalUserCount,
    SUM(fa.TotalScore) OVER () as TotalScoreSum,
    CASE WHEN fa.BadgeCount > (SELECT AVG(BadgeCount) FROM UserStats) THEN 1 ELSE 0 END as AboveAvgBadges,
    CASE WHEN fa.QuestionCount > (SELECT AVG(QuestionCount) FROM UserStats) THEN 1 ELSE 0 END as AboveAvgQuestions,
    CASE WHEN fa.AnswerCount > (SELECT AVG(AnswerCount) FROM UserStats) THEN 1 ELSE 0 END as AboveAvgAnswers
FROM FinalAnalysis fa
WHERE fa.ScoreRank <= 20 
    OR fa.BadgeRank <= 20
    OR fa.RankByScore <= 20
    OR fa.RankByBadges <= 20
ORDER BY fa.TotalScore DESC, fa.BadgeCount DESC, fa.QuestionCount DESC
LIMIT 500;
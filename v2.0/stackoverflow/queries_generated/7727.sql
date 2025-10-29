-- {"query": "7727.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2038} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        MAX(p.CreationDate) as LastPostDate,
        DATEDIFF(day, u.CreationDate, GETDATE()) as AccountAgeDays,
        CASE 
            WHEN u.Reputation >= 100000 THEN 'Elite'
            WHEN u.Reputation >= 10000 THEN 'High'
            WHEN u.Reputation >= 1000 THEN 'Medium'
            WHEN u.Reputation >= 100 THEN 'Low'
            ELSE 'New'
        END as ReputationTier
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.CreationDate
),
PostComplexity AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CommentCount,
        p.AnswerCount,
        p.CreationDate,
        p.LastActivityDate,
        p.Tags,
        COALESCE(p.AnswerCount, 0) as AnswerCountVal,
        COALESCE(p.CommentCount, 0) as CommentCountVal,
        CASE WHEN p.PostTypeId = 1 THEN 'Question' ELSE 'Answer' END as PostType,
        CASE 
            WHEN p.Score < 0 THEN 'Negative'
            WHEN p.Score = 0 THEN 'Neutral'
            WHEN p.Score BETWEEN 1 AND 5 THEN 'Low'
            WHEN p.Score BETWEEN 6 AND 20 THEN 'Medium'
            WHEN p.Score BETWEEN 21 AND 100 THEN 'High'
            WHEN p.Score > 100 THEN 'Very High'
            ELSE 'Unknown'
        END as ScoreCategory,
        CASE 
            WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN 
                (LEN(p.Tags) - LEN(REPLACE(p.Tags, '>', '')) + 1)
            ELSE 0
        END as TagCount,
        DATEDIFF(day, p.CreationDate, p.LastActivityDate) as DaysSinceLastActivity,
        DATEDIFF(day, p.CreationDate, GETDATE()) as DaysSinceCreation,
        CASE 
            WHEN p.AnswerCount > 0 THEN 
                CAST(p.Score AS FLOAT) / NULLIF(p.AnswerCount, 0)
            ELSE NULL 
        END as ScorePerAnswer,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as UserPostRank
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserPerformanceMetrics AS (
    SELECT 
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.PostCount,
        uas.CommentCount,
        uas.BadgeCount,
        uas.QuestionCount,
        uas.AnswerCount,
        uas.TotalScore,
        uas.AccountAgeDays,
        uas.ReputationTier,
        AVG(pcm.Score) as AvgPostScore,
        MAX(pcm.Score) as MaxPostScore,
        MIN(pcm.Score) as MinPostScore,
        STDEV(pcm.Score) as ScoreStdDev,
        AVG(pcm.ViewCount) as AvgViewCount,
        AVG(pcm.DaysSinceLastActivity) as AvgDaysSinceActivity,
        COUNT(pcm.PostId) as ActivePostCount,
        STRING_AGG(pcm.Title, '; ') WITHIN GROUP (ORDER BY pcm.CreationDate DESC) as RecentTitles,
        CASE 
            WHEN uas.QuestionCount > 0 THEN 
                CAST(uas.TotalScore AS FLOAT) / NULLIF(uas.QuestionCount, 0)
            ELSE 0 
        END as AvgScorePerQuestion,
        CASE 
            WHEN uas.AnswerCount > 0 THEN 
                CAST(uas.TotalScore AS FLOAT) / NULLIF(uas.AnswerCount, 0)
            ELSE 0 
        END as AvgScorePerAnswer
    FROM UserActivityStats uas
    LEFT JOIN PostComplexity pcm ON uas.UserId = pcm.PostId
    GROUP BY uas.UserId, uas.DisplayName, uas.Reputation, uas.PostCount, 
             uas.CommentCount, uas.BadgeCount, uas.QuestionCount, 
             uas.AnswerCount, uas.TotalScore, uas.AccountAgeDays, uas.ReputationTier
),
TopPostsByScore AS (
    SELECT 
        PostId,
        Score,
        Title,
        OwnerUserId,
        ROW_NUMBER() OVER (ORDER BY Score DESC) as RankByScore,
        RANK() OVER (ORDER BY Score DESC) as RankByScoreWithTies,
        DENSE_RANK() OVER (ORDER BY Score DESC) as DenseRankByScore,
        PERCENT_RANK() OVER (ORDER BY Score DESC) as PercentileRank,
        NTILE(10) OVER (ORDER BY Score DESC) as Decile
    FROM Posts 
    WHERE PostTypeId = 1 AND Score IS NOT NULL
),
UserPostDistribution AS (
    SELECT 
        UserId,
        COUNT(*) as TotalPosts,
        COUNT(CASE WHEN PostTypeId = 1 THEN 1 END) as Questions,
        COUNT(CASE WHEN PostTypeId = 2 THEN 1 END) as Answers,
        COUNT(CASE WHEN PostTypeId = 3 THEN 1 END) as Wikis,
        COUNT(*) * 100.0 / (SELECT COUNT(*) FROM Posts) as PercentOfAllPosts,
        AVG(Score) as AvgScore,
        SUM(Score) as TotalScore,
        MAX(Score) as MaxScore,
        MIN(Score) as MinScore
    FROM Posts 
    GROUP BY UserId
)
SELECT 
    upm.UserId,
    upm.DisplayName,
    upm.Reputation,
    upm.PostCount,
    upm.QuestionCount,
    upm.AnswerCount,
    upm.BadgeCount,
    upm.TotalScore,
    upm.AvgScorePerQuestion,
    upm.AvgScorePerAnswer,
    upm.AvgPostScore,
    upm.MaxPostScore,
    upm.MinPostScore,
    upm.ScoreStdDev,
    upm.AccountAgeDays,
    upm.ReputationTier,
    upm.RecentTitles,
    tps.RankByScore,
    tps.RankByScoreWithTies,
    tps.DenseRankByScore,
    tps.PercentileRank,
    tps.Decile,
    tps.Score as TopScore,
    tps.Title as TopTitle,
    CASE 
        WHEN upm.PostCount > 0 AND upm.TotalScore > 0 THEN 
            CAST(upm.TotalScore AS FLOAT) / NULLIF(upm.PostCount, 0)
        ELSE 0 
    END as AvgScorePerPost,
    CASE 
        WHEN upm.Reputation > 10000 THEN 'Legendary'
        WHEN upm.Reputation > 5000 THEN 'Veteran'
        WHEN upm.Reputation > 1000 THEN 'Contributor'
        ELSE 'Member'
    END as ReputationLevel,
    CASE 
        WHEN upm.QuestionCount > 100 THEN 'Expert'
        WHEN upm.QuestionCount > 50 THEN 'Advanced'
        WHEN upm.QuestionCount > 10 THEN 'Intermediate'
        ELSE 'Beginner'
    END as QuestionExpertise,
    CASE 
        WHEN upm.AnswerCount > 1000 THEN 'Master'
        WHEN upm.AnswerCount > 500 THEN 'Senior'
        WHEN upm.AnswerCount > 100 THEN 'Experienced'
        ELSE 'Novice'
    END as AnswerExpertise,
    upm.ActivePostCount,
    upm.AvgViewCount,
    upm.AvgDaysSinceActivity,
    CASE 
        WHEN upm.ActivePostCount > 0 AND upm.AvgDaysSinceActivity > 30 THEN 'Inactive'
        WHEN upm.ActivePostCount > 0 AND upm.AvgDaysSinceActivity > 7 THEN 'Moderately Active'
        ELSE 'Active'
    END as ActivityLevel,
    CASE 
        WHEN upm.BadgeCount > 50 THEN 'Gold Badge Holder'
        WHEN upm.BadgeCount > 20 THEN 'Silver Badge Holder'
        WHEN upm.BadgeCount > 5 THEN 'Bronze Badge Holder'
        ELSE 'Bronze Badge Holder'
    END as BadgeLevel,
    CASE 
        WHEN upm.PostCount > 1000 THEN 'Top Contributor'
        WHEN upm.PostCount > 500 THEN 'High Contributor'
        WHEN upm.PostCount > 100 THEN 'Regular Contributor'
        ELSE 'Occasional Contributor'
    END as ContributionLevel
FROM UserPerformanceMetrics upm
LEFT JOIN TopPostsByScore tps ON upm.UserId = tps.PostId
WHERE upm.PostCount > 0
ORDER BY upm.TotalScore DESC, upm.Reputation DESC, upm.AccountAgeDays ASC
OFFSET 0 ROWS FETCH NEXT 1000 ROWS ONLY;
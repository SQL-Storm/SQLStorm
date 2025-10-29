-- {"query": "7950.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2294} 
WITH UserStats AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.DisplayName,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        MAX(p.CreationDate) as LastPostDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as ReputationRank,
        DENSE_RANK() OVER (ORDER BY u.Views DESC) as ViewRank,
        CASE 
            WHEN u.Reputation >= 10000 THEN 'Veteran'
            WHEN u.Reputation >= 1000 THEN 'Expert'
            WHEN u.Reputation >= 100 THEN 'Novice'
            ELSE 'Newbie'
        END as UserTier
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 0
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes
),
TopPosts AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END as PostType,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) as ScoreRank,
        PERCENT_RANK() OVER (ORDER BY p.ViewCount) as ViewPercentile,
        DENSE_RANK() OVER (ORDER BY p.CreationDate) as CreationRank
    FROM Posts p
    WHERE p.Score > 0 AND p.PostTypeId IN (1, 2)
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            WHEN t.Count > 10 THEN 'Niche'
            ELSE 'Rare'
        END as TagPopularity,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as PopularityRank
    FROM Tags t
    WHERE t.Count > 0
),
UserActivity AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        COUNT(DISTINCT ph.Id) as HistoryCount,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (1, 2, 3) THEN ph.Id END) as EditCount,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13) THEN ph.Id END) as StatusChangeCount,
        AVG(DATEDIFF('DAY', ph.CreationDate, CURRENT_TIMESTAMP)) as AvgDaysSinceActivity
    FROM Users u
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    WHERE ph.CreationDate > DATEADD('YEAR', -1, CURRENT_TIMESTAMP)
    GROUP BY u.Id, u.DisplayName
),
PostStats AS (
    SELECT 
        p.PostTypeId,
        COUNT(*) as TotalPosts,
        AVG(p.Score) as AvgScore,
        AVG(p.ViewCount) as AvgViews,
        MAX(p.Score) as MaxScore,
        MIN(p.ViewCount) as MinViews,
        COUNT(DISTINCT p.OwnerUserId) as UniqueOwners,
        COALESCE(SUM(CASE WHEN p.AnswerCount > 0 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 0) as QuestionWithAnswersRatio,
        COALESCE(SUM(CASE WHEN p.CommentCount > 0 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 0) as QuestionWithCommentsRatio
    FROM Posts p
    GROUP BY p.PostTypeId
)
SELECT 
    'Performance Benchmark Report' as ReportTitle,
    COUNT(*) as TotalUsers,
    SUM(CASE WHEN us.UserTier = 'Veteran' THEN 1 ELSE 0 END) as VeteranCount,
    SUM(CASE WHEN us.UserTier = 'Expert' THEN 1 ELSE 0 END) as ExpertCount,
    ROUND(AVG(us.Reputation), 2) as AvgReputation,
    ROUND(AVG(us.Views), 2) as AvgViews,
    ROUND(AVG(us.UpVotes), 2) as AvgUpVotes,
    ROUND(AVG(us.DownVotes), 2) as AvgDownVotes,
    (SELECT COUNT(*) FROM TopPosts WHERE ScoreRank <= 100) as Top100Posts,
    (SELECT MIN(Score) FROM TopPosts WHERE ScoreRank <= 100) as MinScoreTop100,
    (SELECT AVG(Score) FROM TopPosts WHERE ScoreRank <= 100) as AvgScoreTop100,
    (SELECT COUNT(*) FROM TagAnalysis WHERE TagPopularity = 'Popular') as PopularTags,
    (SELECT COUNT(*) FROM TagAnalysis WHERE TagPopularity = 'Moderate') as ModerateTags,
    (SELECT COUNT(*) FROM TagAnalysis WHERE TagPopularity = 'Niche') as NicheTags,
    (SELECT COUNT(*) FROM TagAnalysis WHERE TagPopularity = 'Rare') as RareTags,
    (SELECT MAX(AvgDaysSinceActivity) FROM UserActivity) as MaxActivityDays,
    (SELECT AVG(HistoryCount) FROM UserActivity) as AvgUserHistoryCount,
    (SELECT MAX(UniqueOwners) FROM PostStats) as MaxOwnersPerPostType,
    (SELECT MAX(QuestionWithAnswersRatio) FROM PostStats) as MaxAnswerRatio,
    'Generated on: ' || CURRENT_TIMESTAMP as GeneratedTimestamp,
    -- Complex correlated subquery to get the top 5 most active users by reputation
    (SELECT STRING_AGG(CONCAT(u.DisplayName, ' (', u.Reputation, ')'), '; ') 
     FROM Users u 
     WHERE (SELECT COUNT(*) FROM PostHistory ph WHERE ph.UserId = u.Id) > (SELECT AVG(HistoryCount) FROM UserActivity)
     ORDER BY u.Reputation DESC LIMIT 5) as HighActivityUsers,
    -- Set union to combine different post types and their stats
    (SELECT 'Questions' as PostType, COUNT(*) as Count FROM Posts WHERE PostTypeId = 1
     UNION ALL
     SELECT 'Answers' as PostType, COUNT(*) as Count FROM Posts WHERE PostTypeId = 2
     UNION ALL
     SELECT 'WIKI' as PostType, COUNT(*) as Count FROM Posts WHERE PostTypeId = 3) as PostTypeBreakdown,
    -- String concatenation and manipulation
    CONCAT('Reputation Score Range: ', 
           (SELECT MIN(Reputation) FROM Users), ' - ', 
           (SELECT MAX(Reputation) FROM Users), 
           ' | Avg: ', 
           ROUND(AVG(Reputation), 2)) as ReputationAnalysis,
    -- Complex window functions and calculations
    ROUND((SELECT AVG(AvgScore) FROM PostStats), 2) as OverallAvgScore,
    ROUND((SELECT MAX(MaxScore) FROM PostStats), 2) as HighestScore,
    -- NULL handling with COALESCE
    COALESCE((SELECT AVG(AvgScore) FROM PostStats), 0) as SafeAvgScore,
    -- Multiple joins and outer joins
    (SELECT COUNT(DISTINCT ph.PostId) 
     FROM PostHistory ph 
     LEFT JOIN Posts p ON ph.PostId = p.Id 
     WHERE ph.PostHistoryTypeId = 1 AND p.PostTypeId = 1) as TitleEditCount
FROM UserStats us
WHERE us.ReputationRank <= 1000
HAVING COUNT(*) > 100
UNION ALL
-- Additional complex expression with set operators
SELECT 
    'Extended Analysis' as ReportTitle,
    COUNT(DISTINCT u.Id) as TotalUsers,
    COUNT(DISTINCT CASE WHEN u.Reputation >= 10000 THEN u.Id END) as EliteCount,
    ROUND(AVG(CASE WHEN u.Reputation >= 1000 THEN u.Reputation END), 2) as AvgExpertReputation,
    COUNT(DISTINCT CASE WHEN u.Views > 1000 THEN u.Id END) as ActiveUsers,
    COUNT(DISTINCT CASE WHEN u.UpVotes > u.DownVotes THEN u.Id END) as PositiveReputationUsers,
    COUNT(DISTINCT CASE WHEN u.DownVotes > 0 THEN u.Id END) as DownVoteUsers,
    ROUND(AVG(CASE WHEN u.Reputation IS NOT NULL THEN u.Reputation END), 2) as SafeAvgReputation,
    ROUND(AVG(CASE WHEN u.Views IS NOT NULL THEN u.Views END), 2) as SafeAvgViews,
    ROUND(AVG(CASE WHEN u.UpVotes IS NOT NULL THEN u.UpVotes END), 2) as SafeAvgUpVotes,
    ROUND(AVG(CASE WHEN u.DownVotes IS NOT NULL THEN u.DownVotes END), 2) as SafeAvgDownVotes,
    COUNT(DISTINCT CASE WHEN c.Id IS NOT NULL THEN u.Id END) as CommentingUsers,
    COUNT(DISTINCT CASE WHEN b.Id IS NOT NULL THEN u.Id END) as BadgeHolders,
    CONCAT('Top User: ', 
           (SELECT TOP 1 DisplayName FROM Users ORDER BY Reputation DESC)) as TopUser,
    'Extended Report' as GeneratedTimestamp,
    CASE 
        WHEN (SELECT AVG(Reputation) FROM Users) > 5000 THEN 'High'
        WHEN (SELECT AVG(Reputation) FROM Users) > 1000 THEN 'Medium'
        ELSE 'Low'
    END as ReputationLevel,
    ROUND(SUM(CASE WHEN u.Views > 1000 THEN u.Views ELSE 0 END) * 100.0 / NULLIF(SUM(u.Views), 0), 2) as ActiveUsersShare,
    (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 1) * 100.0 / NULLIF((SELECT COUNT(*) FROM Posts), 0) as QuestionPercentage,
    (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 2) * 100.0 / NULLIF((SELECT COUNT(*) FROM Posts), 0) as AnswerPercentage
FROM Users u
LEFT JOIN Comments c ON u.Id = c.UserId
LEFT JOIN Badges b ON u.Id = b.UserId
WHERE u.Reputation > 0
GROUP BY u.Id
HAVING COUNT(*) > 50
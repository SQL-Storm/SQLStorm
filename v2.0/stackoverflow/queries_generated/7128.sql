-- {"query": "7128.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2666} 
WITH UserStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN p.Id END) as QuestionWithAcceptedAnswer,
        STRING_AGG(DISTINCT COALESCE(p.Tags, ''), ', ') as AllTags,
        AVG(CAST(p.Score AS FLOAT)) as AvgPostScore,
        COUNT(DISTINCT CASE WHEN p.Score > 0 THEN p.Id END) as PositiveScoredPosts,
        COALESCE(SUM(p.ViewCount), 0) as TotalViews,
        COALESCE(SUM(p.FavoriteCount), 0) as TotalFavorites,
        DATEDIFF(DAY, u.CreationDate, GETDATE()) as AccountAgeDays,
        CASE 
            WHEN u.Reputation > 10000 THEN 'Elite'
            WHEN u.Reputation > 1000 THEN 'Veteran'
            WHEN u.Reputation > 100 THEN 'Regular'
            ELSE 'Newbie'
        END as ReputationTier
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.CreationDate
),
RankedUsers AS (
    SELECT *,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, PostCount DESC, Views DESC) as RankByReputation,
        RANK() OVER (ORDER BY TotalViews DESC) as RankByViews,
        DENSE_RANK() OVER (ORDER BY QuestionCount DESC) as RankByQuestions
    FROM UserStats
),
TopPosts AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Body,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ParentId,
        p.AcceptedAnswerId,
        u.DisplayName as OwnerName,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END as PostTypeDesc,
        DATEDIFF(DAY, p.CreationDate, GETDATE()) as AgeInDays,
        DATEDIFF(DAY, p.CreationDate, COALESCE(p.LastActivityDate, p.CreationDate)) as ActivityDurationDays,
        COALESCE(p.AnswerCount, 0) + COALESCE(p.CommentCount, 0) as EngagementCount,
        CASE 
            WHEN p.Score <= -5 THEN 'Downvoted'
            WHEN p.Score <= 0 THEN 'Neutral'
            WHEN p.Score <= 10 THEN 'Positive'
            WHEN p.Score <= 50 THEN 'Highly Positive'
            ELSE 'Exceptional'
        END as ScoreCategory
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2) AND p.CreationDate >= DATEADD(MONTH, -6, GETDATE())
),
AggregatedData AS (
    SELECT 
        'AllUsers' as DataSource,
        COUNT(*) as TotalUsers,
        COUNT(CASE WHEN Reputation > 1000 THEN 1 END) as HighReputationUsers,
        AVG(Reputation) as AvgReputation,
        AVG(PostCount) as AvgPostsPerUser,
        AVG(Views) as AvgViewsPerUser,
        AVG(UpVotes) as AvgUpVotesPerUser
    FROM UserStats
    UNION ALL
    SELECT 
        'ActiveUsers' as DataSource,
        COUNT(*) as TotalUsers,
        COUNT(CASE WHEN Reputation > 1000 THEN 1 END) as HighReputationUsers,
        AVG(Reputation) as AvgReputation,
        AVG(PostCount) as AvgPostsPerUser,
        AVG(Views) as AvgViewsPerUser,
        AVG(UpVotes) as AvgUpVotesPerUser
    FROM UserStats 
    WHERE LastPostDate >= DATEADD(WEEK, -2, GETDATE())
    UNION ALL
    SELECT 
        'QuestionPosts' as DataSource,
        COUNT(*) as TotalUsers,
        0 as HighReputationUsers,
        AVG(Score) as AvgReputation,
        AVG(ViewCount) as AvgPostsPerUser,
        AVG(FavoriteCount) as AvgViewsPerUser,
        AVG(AnswerCount) as AvgUpVotesPerUser
    FROM TopPosts 
    WHERE PostTypeId = 1
    UNION ALL
    SELECT 
        'AnswerPosts' as DataSource,
        COUNT(*) as TotalUsers,
        0 as HighReputationUsers,
        AVG(Score) as AvgReputation,
        AVG(ViewCount) as AvgPostsPerUser,
        AVG(FavoriteCount) as AvgViewsPerUser,
        AVG(CommentCount) as AvgUpVotesPerUser
    FROM TopPosts 
    WHERE PostTypeId = 2
),
ComplexJoinResult AS (
    SELECT 
        ru.UserId,
        ru.DisplayName,
        ru.Reputation,
        ru.PostCount,
        ru.QuestionCount,
        ru.AnswerCount,
        ru.AvgPostScore,
        ru.TotalViews,
        ru.TotalFavorites,
        ru.ReputationTier,
        ru.RankByReputation,
        ru.RankByViews,
        ru.RankByQuestions,
        COALESCE(tp.Title, 'No Title') as RecentPostTitle,
        COALESCE(tp.Score, 0) as RecentPostScore,
        COALESCE(tp.ViewCount, 0) as RecentPostViews,
        tp.PostTypeDesc,
        tp.AgeInDays,
        tp.ScoreCategory,
        CASE 
            WHEN ABS(tp.Score) > 100 AND tp.AgeInDays < 30 THEN 'High Impact Recent'
            WHEN tp.Score > 10 AND tp.ActivityDurationDays > 7 THEN 'Active Contributor'
            WHEN tp.Score > 5 AND tp.AgeInDays < 90 THEN 'Recent Activity'
            ELSE 'Regular'
        END as ActivityLevel,
        CASE 
            WHEN tp.PostTypeId = 1 AND tp.AnswerCount > 0 AND tp.Score > 10 THEN 'Question with Quality Answers'
            WHEN tp.PostTypeId = 2 AND tp.Score > 20 THEN 'High Score Answer'
            WHEN tp.PostTypeId = 1 AND tp.Score > 50 THEN 'Popular Question'
            ELSE 'Standard Post'
        END as PostClassification,
        ISNULL(SUBSTRING(tp.Tags, 2, LEN(tp.Tags) - 2), '') as CleanTags,
        CASE 
            WHEN tp.PostTypeId = 1 THEN 
                (SELECT TOP 1 COUNT(*) 
                 FROM Comments c 
                 WHERE c.PostId = tp.PostId)
            ELSE 0 
        END as CommentCountOnPost
    FROM RankedUsers ru
    LEFT JOIN TopPosts tp ON ru.UserId = tp.OwnerUserId 
    WHERE ru.Reputation > 1000 
       OR (ru.QuestionCount > 5 AND ru.AnswerCount > 10)
       OR ru.PostCount > 100
),
FinalResult AS (
    SELECT 
        *,
        DENSE_RANK() OVER (ORDER BY Reputation DESC, PostCount DESC) as OverallRank,
        CASE 
            WHEN RepTier = 'Elite' THEN 
                (SELECT COUNT(*) FROM UserStats WHERE ReputationTier = 'Elite') 
            WHEN RepTier = 'Veteran' THEN 
                (SELECT COUNT(*) FROM UserStats WHERE ReputationTier = 'Veteran') 
            WHEN RepTier = 'Regular' THEN 
                (SELECT COUNT(*) FROM UserStats WHERE ReputationTier = 'Regular') 
            ELSE 
                (SELECT COUNT(*) FROM UserStats WHERE ReputationTier = 'Newbie') 
        END as TierPopulation,
        COALESCE(RecentPostScore, 0) + COALESCE(RecentPostViews, 0) as EngagementMetric,
        CASE 
            WHEN OverallRank <= 5 THEN 'Top 5'
            WHEN OverallRank <= 25 THEN 'Top 25'
            WHEN OverallRank <= 100 THEN 'Top 100'
            ELSE 'Others'
        END as RankGroup,
        IIF(RecentPostViews > RecentPostScore, 'Views Dominant', 'Score Dominant') as PerformanceMetric,
        CASE 
            WHEN RecentPostScore > 100 THEN 'Extremely High'
            WHEN RecentPostScore > 50 THEN 'High'
            WHEN RecentPostScore > 10 THEN 'Moderate'
            WHEN RecentPostScore > 0 THEN 'Low'
            ELSE 'Negative'
        END as ScoreLevel,
        COALESCE(RecentPostTitle, 'No Recent Activity') as CurrentActivity,
        ISNULL(CleanTags, 'No Tags') as TagInfo,
        ISNULL(CONVERT(VARCHAR, CommentCountOnPost), '0') as DirectCommentCount
    FROM ComplexJoinResult
)
SELECT 
    UserId,
    DisplayName,
    Reputation,
    PostCount,
    QuestionCount,
    AnswerCount,
    AvgPostScore,
    TotalViews,
    TotalFavorites,
    ReputationTier,
    RankByReputation,
    RankByViews,
    RankByQuestions,
    RecentPostTitle,
    RecentPostScore,
    RecentPostViews,
    PostTypeDesc,
    AgeInDays,
    ScoreCategory,
    ActivityLevel,
    PostClassification,
    CleanTags,
    CommentCountOnPost,
    OverallRank,
    TierPopulation,
    EngagementMetric,
    RankGroup,
    PerformanceMetric,
    ScoreLevel,
    CurrentActivity,
    TagInfo,
    DirectCommentCount,
    CASE 
        WHEN AgeInDays > 365 THEN 'Long Term Contributor'
        WHEN AgeInDays > 90 THEN 'Active Contributor'
        WHEN AgeInDays > 30 THEN 'Recent Active'
        ELSE 'New Contributor'
    END as ContributionDuration,
    CASE 
        WHEN CommentCountOnPost > 10 THEN 'Highly Engaged'
        WHEN CommentCountOnPost > 5 THEN 'Moderately Engaged'
        WHEN CommentCountOnPost > 0 THEN 'Slightly Engaged'
        ELSE 'Not Engaged'
    END as EngagementStatus,
    NULLIF(
        CASE 
            WHEN TotalFavorites > 0 THEN CAST(TotalFavorites AS FLOAT) / CAST(TotalViews AS FLOAT) * 100
            ELSE 0
        END, 0
    ) as FavoriteRatePercent,
    NULLIF(
        CASE 
            WHEN PostCount > 0 THEN CAST(AnswerCount AS FLOAT) / CAST(PostCount AS FLOAT) * 100
            ELSE 0
        END, 0
    ) as AnswerRatePercent,
    CAST(Reputation AS DECIMAL(18,2)) / 
    NULLIF(CAST(AccountAgeDays AS DECIMAL(18,2)), 0) as ReputationPerDay,
    COALESCE(
        (SELECT COUNT(DISTINCT Id) 
         FROM Badges b 
         WHERE b.UserId = UserId 
           AND b.Date >= DATEADD(MONTH, -3, GETDATE())), 
        0
    ) as RecentBadgeCount,
    CASE 
        WHEN PostCount > 50 AND AvgPostScore > 5 THEN 'Productive'
        WHEN PostCount > 25 AND AvgPostScore > 2 THEN 'Moderately Productive'
        ELSE 'Standard'
    END as ProductivityLevel,
    DATEDIFF(DAY, LastPostDate, GETDATE()) as DaysSinceLastPost,
    DATEDIFF(DAY, LastCommentDate, GETDATE()) as DaysSinceLastComment,
    REPLICATE('*', CAST(Reputation / 1000 AS INT)) as ReputationStarRating
FROM FinalResult
WHERE OverallRank <= 200
ORDER BY OverallRank, Reputation DESC, PostCount DESC
OPTION (MAXDOP 4)
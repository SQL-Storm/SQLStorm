-- {"query": "7405.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2395} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        COALESCE(SUM(p.ViewCount), 0) as TotalViews,
        COUNT(DISTINCT c.Id) as CommentsMade,
        COUNT(DISTINCT b.Id) as BadgesEarned,
        MAX(p.CreationDate) as LastPostDate,
        DATEDIFF(day, u.CreationDate, GETDATE()) as AccountAgeDays,
        CASE 
            WHEN COUNT(DISTINCT p.Id) = 0 THEN 'No Posts'
            WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0 AND COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) = 0 THEN 'Question Only'
            WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) = 0 AND COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) > 0 THEN 'Answer Only'
            ELSE 'Both Questions and Answers'
        END as PostTypeCategory,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) OVER (PARTITION BY u.Id) as MedianScore,
        LAG(u.Reputation, 1) OVER (ORDER BY u.Reputation DESC) as NextHigherReputation,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as ReputationRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
RankedUsers AS (
    SELECT 
        *,
        CASE 
            WHEN TotalPosts = 0 THEN 0
            ELSE CAST(TotalScore AS FLOAT) / CAST(TotalPosts AS FLOAT)
        END as AvgScorePerPost,
        CASE 
            WHEN TotalViews = 0 THEN 0
            ELSE CAST(TotalScore AS FLOAT) / CAST(TotalViews AS FLOAT)
        END as ScorePerView,
        CASE 
            WHEN AccountAgeDays = 0 THEN 0
            ELSE CAST(TotalPosts AS FLOAT) / CAST(AccountAgeDays AS FLOAT)
        END as PostsPerDay,
        CASE 
            WHEN TotalPosts > 0 THEN CAST(CommentsMade AS FLOAT) / CAST(TotalPosts AS FLOAT)
            ELSE 0
        END as CommentsPerPost,
        CASE WHEN Reputation > 1000 AND TotalPosts > 0 THEN 'Active' ELSE 'Inactive' END as ActivityStatus,
        CASE 
            WHEN TotalPosts = 0 THEN 'No Activity'
            WHEN TotalPosts >= 1000 THEN 'Legendary'
            WHEN TotalPosts >= 500 THEN 'Master'
            WHEN TotalPosts >= 100 THEN 'Expert'
            WHEN TotalPosts >= 10 THEN 'Intermediate'
            ELSE 'Beginner'
        END as PostLevel,
        DENSE_RANK() OVER (ORDER BY TotalScore DESC) as ScoreRank
    FROM UserActivityStats
),
PostAnalysis AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.ParentId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        LEN(p.Body) as BodyLength,
        CASE 
            WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN 
                ARRAY_LENGTH(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><'), 1)
            ELSE 0 
        END as TagCount,
        CASE 
            WHEN p.Score > 100 THEN 'High'
            WHEN p.Score > 50 THEN 'Medium'
            WHEN p.Score > 10 THEN 'Low'
            ELSE 'Very Low'
        END as ScoreCategory,
        CASE 
            WHEN p.ViewCount > 1000 THEN 'Popular'
            WHEN p.ViewCount > 100 THEN 'Moderate'
            WHEN p.ViewCount > 10 THEN 'Low'
            ELSE 'Very Low'
        END as PopularityCategory,
        NTILE(5) OVER (ORDER BY p.Score DESC) as ScoreQuintile,
        PERCENT_RANK() OVER (ORDER BY p.ViewCount) as ViewPercentile,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as UserPostSequence,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PrevScore,
        COALESCE(p.Score - LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate), 0) as ScoreChange,
        EXTRACT(YEAR FROM p.CreationDate) as PostYear,
        EXTRACT(MONTH FROM p.CreationDate) as PostMonth
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) AND p.OwnerUserId IS NOT NULL
),
UserPostStats AS (
    SELECT 
        r.UserId,
        r.DisplayName,
        r.Reputation,
        r.TotalPosts,
        r.Questions,
        r.Answers,
        r.TotalScore,
        r.TotalViews,
        r.CommentsMade,
        r.BadgesEarned,
        r.PostTypeCategory,
        r.AvgScorePerPost,
        r.ScorePerView,
        r.PostsPerDay,
        r.CommentsPerPost,
        r.ActivityStatus,
        r.PostLevel,
        r.ScoreRank,
        SUM(pa.Score) as UserTotalScore,
        AVG(pa.Score) as UserAvgScore,
        MAX(pa.Score) as UserMaxScore,
        MIN(pa.Score) as UserMinScore,
        COUNT(pa.Id) as UserTotalPosts,
        AVG(pa.ViewCount) as UserAvgViews,
        SUM(pa.ViewCount) as UserTotalViews,
        STRING_AGG(DISTINCT pa.Title, ', ') as UserPostTitles,
        STRING_AGG(DISTINCT pa.Tags, ', ') as UserPostTags,
        MIN(pa.CreationDate) as FirstPostDate,
        MAX(pa.CreationDate) as LatestPostDate,
        DATEDIFF(day, MIN(pa.CreationDate), MAX(pa.CreationDate)) as ActivePeriodDays,
        COUNT(CASE WHEN pa.PostTypeId = 1 THEN 1 END) as UserQuestions,
        COUNT(CASE WHEN pa.PostTypeId = 2 THEN 1 END) as UserAnswers
    FROM RankedUsers r
    INNER JOIN PostAnalysis pa ON r.UserId = pa.OwnerUserId
    WHERE r.UserId IS NOT NULL
    GROUP BY 
        r.UserId, r.DisplayName, r.Reputation, r.TotalPosts, r.Questions, r.Answers, 
        r.TotalScore, r.TotalViews, r.CommentsMade, r.BadgesEarned, 
        r.PostTypeCategory, r.AvgScorePerPost, r.ScorePerView, r.PostsPerDay,
        r.CommentsPerPost, r.ActivityStatus, r.PostLevel, r.ScoreRank
),
TemporalAnalysis AS (
    SELECT 
        PostYear,
        PostMonth,
        COUNT(*) as TotalPosts,
        AVG(Score) as AvgScore,
        AVG(ViewCount) as AvgViews,
        SUM(Score) as TotalScore,
        SUM(ViewCount) as TotalViews,
        COUNT(DISTINCT OwnerUserId) as UniqueAuthors,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY Score) as MedianScore,
        CUME_DIST() OVER (ORDER BY AVG(Score)) as ScoreDistribution,
        LAG(AvgScore, 1) OVER (ORDER BY PostYear, PostMonth) as PrevMonthAvgScore,
        (AvgScore - LAG(AvgScore, 1) OVER (ORDER BY PostYear, PostMonth)) / NULLIF(LAG(AvgScore, 1) OVER (ORDER BY PostYear, PostMonth), 0) * 100 as ScoreGrowthPercent,
        ROW_NUMBER() OVER (ORDER BY PostYear, PostMonth) as MonthSequence
    FROM PostAnalysis
    GROUP BY PostYear, PostMonth
)
SELECT 
    'Performance Benchmark Report' as ReportTitle,
    COUNT(*) as TotalUsers,
    COUNT(CASE WHEN ActivityStatus = 'Active' THEN 1 END) as ActiveUsers,
    AVG(Reputation) as AvgReputation,
    MAX(Reputation) as MaxReputation,
    AVG(TotalPosts) as AvgPostsPerUser,
    AVG(TotalScore) as AvgScorePerUser,
    COUNT(CASE WHEN PostLevel = 'Legendary' THEN 1 END) as LegendaryUsers,
    COUNT(CASE WHEN PostLevel = 'Master' THEN 1 END) as MasterUsers,
    COUNT(CASE WHEN PostLevel = 'Expert' THEN 1 END) as ExpertUsers,
    COUNT(CASE WHEN PostLevel = 'Intermediate' THEN 1 END) as IntermediateUsers,
    COUNT(CASE WHEN PostLevel = 'Beginner' THEN 1 END) as BeginnerUsers,
    COUNT(CASE WHEN PostLevel = 'No Activity' THEN 1 END) as NoActivityUsers,
    STRING_AGG(DISTINCT PostTypeCategory, ', ') as PostTypeCategories,
    COUNT(DISTINCT PostTypeId) as PostTypeCount,
    COUNT(DISTINCT TagCount) as TagCounts,
    AVG(CommentsPerPost) as AvgCommentsPerPost,
    AVG(AvgScorePerPost) as AvgScorePerPost,
    AVG(ScorePerView) as AvgScorePerView,
    AVG(PostsPerDay) as AvgPostsPerDay,
    COUNT(DISTINCT OwnerUserId) as UniquePostOwners,
    COUNT(*) as TotalPostsAnalysed,
    AVG(ViewPercentile) as AvgViewPercentile,
    MAX(ScoreQuintile) as MaxScoreQuintile,
    AVG(ScoreChange) as AvgScoreChange,
    COUNT(DISTINCT PostYear) as YearsAnalyzed,
    COUNT(DISTINCT PostMonth) as MonthsAnalyzed,
    AVG(TotalScore) as AvgScorePerMonth,
    AVG(TotalViews) as AvgViewsPerMonth,
    AVG(UniqueAuthors) as AvgUniqueAuthorsPerMonth,
    AVG(ScoreDistribution) as AvgScoreDistribution,
    AVG(ScoreGrowthPercent) as AvgScoreGrowthPercent,
    '--- Complex Query Complete ---' as FinalNote
FROM UserPostStats ups
FULL OUTER JOIN PostAnalysis pa ON ups.UserId IS NOT NULL
FULL OUTER JOIN TemporalAnalysis ta ON pa.PostYear IS NOT NULL
FULL OUTER JOIN RankedUsers ru ON ups.UserId = ru.UserId
WHERE ups.UserId IS NOT NULL OR pa.Id IS NOT NULL OR ta.PostYear IS NOT NULL
GROUP BY 
    CASE 
        WHEN COUNT(DISTINCT ups.UserId) > 0 THEN 'Users'
        WHEN COUNT(DISTINCT pa.Id) > 0 THEN 'Posts'
        WHEN COUNT(DISTINCT ta.PostYear) > 0 THEN 'Temporal'
        ELSE 'Mixed'
    END;
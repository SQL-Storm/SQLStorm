-- {"query": "7243.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1641} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.CreationDate,
        u.DisplayName,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        COUNT(DISTINCT b.Id) as Badges,
        COUNT(DISTINCT c.Id) as Comments,
        COUNT(DISTINCT v.Id) as Votes,
        COALESCE(MAX(p.CreationDate), u.CreationDate) as LastActivity,
        DATEDIFF(CURRENT_TIMESTAMP, u.CreationDate) as AccountAgeDays,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 100 THEN 'High'
            WHEN COUNT(DISTINCT p.Id) > 50 THEN 'Medium'
            WHEN COUNT(DISTINCT p.Id) > 10 THEN 'Low'
            ELSE 'Very Low'
        END as ActivityLevel
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.Id > 0
    GROUP BY u.Id, u.Reputation, u.CreationDate, u.DisplayName
),
RankedUsers AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, TotalPosts DESC) as RankByReputation,
        ROW_NUMBER() OVER (ORDER BY TotalPosts DESC, Reputation DESC) as RankByActivity,
        PERCENT_RANK() OVER (ORDER BY Reputation) as ReputationPercentile,
        NTILE(10) OVER (ORDER BY Reputation) as ReputationDecile
    FROM UserActivityStats
),
TopQuestionTags AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        AVG(p.Score) as AvgScore,
        AVG(p.ViewCount) as AvgViews,
        COUNT(DISTINCT p.OwnerUserId) as ActiveUsers,
        STRING_AGG(DISTINCT u.DisplayName, ', ') as ActiveUserNames
    FROM Tags t
    INNER JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    INNER JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 AND p.Score > 0
    GROUP BY t.TagName, t.Count
    HAVING COUNT(DISTINCT p.OwnerUserId) >= 5
),
PostComplexityAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Body,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Tags,
        CASE 
            WHEN LENGTH(p.Body) > 1000 THEN 'Long'
            WHEN LENGTH(p.Body) > 500 THEN 'Medium'
            ELSE 'Short'
        END as BodyLengthCategory,
        CASE 
            WHEN p.CommentCount > 10 THEN 'High'
            WHEN p.CommentCount > 5 THEN 'Medium'
            ELSE 'Low'
        END as CommentLevel,
        CASE 
            WHEN p.Score > 50 THEN 'Very Popular'
            WHEN p.Score > 20 THEN 'Popular'
            WHEN p.Score > 5 THEN 'Moderate'
            ELSE 'Low'
        END as PopularityCategory,
        DATEDIFF(CURRENT_TIMESTAMP, p.CreationDate) as DaysOld
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Score IS NOT NULL
),
EngagementMetrics AS (
    SELECT 
        p.PostId,
        p.Title,
        p.OwnerUserId,
        u.DisplayName as AuthorName,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.PopularityCategory,
        p.DaysOld,
        CASE 
            WHEN p.AnswerCount > 0 AND p.Score > 0 THEN 
                CAST(p.CommentCount AS FLOAT) / CAST(p.AnswerCount AS FLOAT)
            ELSE NULL 
        END as CommentsPerAnswer,
        CASE 
            WHEN p.Score > 0 THEN 
                CAST(p.ViewCount AS FLOAT) / CAST(p.Score AS FLOAT)
            ELSE NULL 
        END as ViewsPerScore,
        CASE 
            WHEN p.FavoriteCount > 0 THEN 
                CAST(p.Score AS FLOAT) / CAST(p.FavoriteCount AS FLOAT)
            ELSE NULL 
        END as ScorePerFavorite
    FROM PostComplexityAnalysis p
    INNER JOIN Users u ON p.OwnerUserId = u.Id
)
SELECT 
    'User Performance Analysis' as AnalysisType,
    COUNT(*) as TotalUsers,
    AVG(Reputation) as AvgReputation,
    MAX(Reputation) as MaxReputation,
    COUNT(DISTINCT CASE WHEN Reputation > 10000 THEN 1 END) as HighReputationUsers,
    COUNT(DISTINCT CASE WHEN RankByReputation <= 100 THEN 1 END) as Top100Users,
    ROUND(AVG(AccountAgeDays), 2) as AvgAccountAgeDays,
    STRING_AGG(DISTINCT ActivityLevel, ', ') as ActivityLevels,
    'Post Metrics Analysis' as AnalysisType2,
    AVG(Score) as AvgPostScore,
    AVG(ViewCount) as AvgPostViews,
    COUNT(*) as TotalPosts,
    AVG(AnswerCount) as AvgAnswersPerPost,
    AVG(CommentCount) as AvgCommentsPerPost,
    AVG(FavoriteCount) as AvgFavoritesPerPost,
    'Tag Analysis' as AnalysisType3,
    COUNT(*) as TotalTags,
    AVG(TagCount) as AvgTagUsage,
    MAX(TagCount) as MaxTagUsage,
    STRING_AGG(DISTINCT PopularityCategory, ', ') as PostPopularityCategories,
    'Combined Metrics' as AnalysisType4,
    COUNT(DISTINCT u.Id) as UniqueUsers,
    COUNT(DISTINCT p.Id) as TotalPostsProcessed,
    COUNT(DISTINCT t.TagName) as UniqueTags,
    AVG(epm.ViewsPerScore) as AvgViewsPerScore,
    AVG(epm.ScorePerFavorite) as AvgScorePerFavorite,
    COUNT(DISTINCT CASE WHEN epm.CommentsPerAnswer IS NOT NULL THEN 1 END) as PostsWithCommentsPerAnswer,
    CASE 
        WHEN COUNT(*) > 0 THEN 
            ROUND((COUNT(DISTINCT CASE WHEN epm.CommentsPerAnswer > 1 THEN 1 END) * 100.0) / COUNT(*), 2)
        ELSE 0 
    END as PercentageHighCommentPosts
FROM RankedUsers u
LEFT JOIN EngagementMetrics epm ON u.UserId = epm.OwnerUserId
LEFT JOIN Posts p ON u.UserId = p.OwnerUserId
LEFT JOIN Tags t ON p.Tags LIKE '%' || t.TagName || '%'
WHERE u.UserId IN (
    SELECT UserId 
    FROM (
        SELECT UserId, 
               COUNT(*) as PostCount,
               RANK() OVER (ORDER BY COUNT(*) DESC) as PostRank
        FROM Posts 
        WHERE PostTypeId = 1 
        GROUP BY UserId
    ) ranked_posts
    WHERE PostRank <= 50
)
AND u.UserId NOT IN (
    SELECT UserId 
    FROM Badges 
    WHERE Name IN ('Autobiographer', 'Organizer', 'Editor', 'Strunk & White', 'Copy Editor')
    GROUP BY UserId
    HAVING COUNT(*) >= 3
)
GROUP BY 
    'User Performance Analysis',
    'Post Metrics Analysis',
    'Tag Analysis',
    'Combined Metrics'
HAVING 
    COUNT(*) > 0
ORDER BY 
    COUNT(*) DESC;
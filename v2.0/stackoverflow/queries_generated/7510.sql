-- {"query": "7510.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2240} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT c.Id) as TotalComments,
        COUNT(DISTINCT b.Id) as TotalBadges,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        DATEDIFF(DAY, u.CreationDate, GETDATE()) as DaysSinceRegistration,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 0 THEN 
                ROUND(CAST(SUM(p.Score) AS FLOAT) / CAST(COUNT(DISTINCT p.Id) AS FLOAT), 2)
            ELSE 0 
        END as AvgScorePerPost,
        STRING_AGG(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Title END, '; ') as QuestionTitles,
        STRING_AGG(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Body END, '; ') as AnswerBodies
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
TopTags AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as RankByPopularity,
        AVG(t.Count) OVER () as AvgTagCount,
        CASE 
            WHEN t.Count > (SELECT AVG(Count) FROM Tags) THEN 'High'
            WHEN t.Count < (SELECT AVG(Count) FROM Tags) THEN 'Low'
            ELSE 'Average'
        END as PopularityLevel
    FROM Tags t
),
PostStats AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.ParentId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        p.AcceptedAnswerId,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END as PostType,
        CASE 
            WHEN p.Score >= 100 THEN 'Highly Valued'
            WHEN p.Score >= 10 THEN 'Valued'
            ELSE 'Standard'
        END as ValueTier,
        COALESCE(p.AnswerCount, 0) as AnswerCountNotNull,
        COALESCE(p.CommentCount, 0) as CommentCountNotNull,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 'Answered'
            WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN 'Has Answers'
            WHEN p.PostTypeId = 1 THEN 'Unanswered'
            ELSE 'N/A'
        END as QuestionStatus,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as UserPostRank
    FROM Posts p
),
UserPostAnalysis AS (
    SELECT 
        ps.Id as PostId,
        ps.PostTypeId,
        ps.ParentId,
        ps.OwnerUserId,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCountNotNull,
        ps.CommentCountNotNull,
        ps.CreationDate,
        ps.Title,
        ps.Tags,
        ps.PostType,
        ps.ValueTier,
        ps.QuestionStatus,
        ps.UserPostRank,
        ROW_NUMBER() OVER (ORDER BY ps.Score DESC) as GlobalScoreRank,
        AVG(ps.Score) OVER (PARTITION BY ps.OwnerUserId) as AvgUserScore,
        RANK() OVER (ORDER BY ps.ViewCount DESC) as ViewRank,
        DENSE_RANK() OVER (ORDER BY ps.CreationDate DESC) as TimeRank
    FROM PostStats ps
),
ComplexUserAnalysis AS (
    SELECT 
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.TotalPosts,
        uas.TotalComments,
        uas.TotalBadges,
        uas.TotalScore,
        uas.LastPostDate,
        uas.LastCommentDate,
        uas.DaysSinceRegistration,
        uas.AvgScorePerPost,
        uas.QuestionTitles,
        uas.AnswerBodies,
        CASE 
            WHEN uas.TotalPosts > 10 AND uas.TotalComments > 5 THEN 'Active Contributor'
            WHEN uas.TotalPosts > 5 THEN 'Regular Poster'
            WHEN uas.TotalPosts > 0 THEN 'Occasional Poster'
            ELSE 'Inactive'
        END as ActivityLevel,
        CASE 
            WHEN uas.Reputation > 10000 THEN 'Expert'
            WHEN uas.Reputation > 1000 THEN 'Advanced'
            WHEN uas.Reputation > 100 THEN 'Intermediate'
            ELSE 'Beginner'
        END as ReputationLevel,
        ROW_NUMBER() OVER (ORDER BY uas.Reputation DESC, uas.TotalPosts DESC) as UserRank,
        PERCENT_RANK() OVER (ORDER BY uas.Reputation DESC) as ReputationPercentile,
        NTILE(4) OVER (ORDER BY uas.Reputation DESC) as ReputationQuartile
    FROM UserActivityStats uas
)
SELECT 
    cua.UserId,
    cua.DisplayName,
    cua.Reputation,
    cua.TotalPosts,
    cua.TotalComments,
    cua.TotalBadges,
    cua.TotalScore,
    cua.LastPostDate,
    cua.LastCommentDate,
    cua.DaysSinceRegistration,
    cua.AvgScorePerPost,
    cua.QuestionTitles,
    cua.AnswerBodies,
    cua.ActivityLevel,
    cua.ReputationLevel,
    cua.UserRank,
    cua.ReputationPercentile,
    cua.ReputationQuartile,
    
    -- Complex calculations and string operations
    CASE 
        WHEN cua.ActivityLevel = 'Active Contributor' THEN CONCAT('Active user with ', cua.TotalPosts, ' posts and ', cua.TotalComments, ' comments')
        WHEN cua.ActivityLevel = 'Regular Poster' THEN CONCAT('Regular user with ', cua.TotalPosts, ' posts')
        WHEN cua.ActivityLevel = 'Occasional Poster' THEN CONCAT('Occasional user with ', cua.TotalPosts, ' posts')
        ELSE 'Inactive user'
    END as ActivitySummary,
    
    CASE 
        WHEN cua.Reputation > 50000 THEN UPPER(CONCAT(cua.ReputationLevel, ' - Elite'))
        WHEN cua.Reputation > 25000 THEN UPPER(CONCAT(cua.ReputationLevel, ' - Expert'))
        WHEN cua.Reputation > 10000 THEN UPPER(CONCAT(cua.ReputationLevel, ' - Master'))
        ELSE cua.ReputationLevel
    END as EnhancedReputationLevel,
    
    -- Set operators and aggregations
    COALESCE(
        (SELECT STRING_AGG(pt.TagName, ', ') 
         FROM (SELECT DISTINCT TRIM(SUBSTRING(t.TagName, 2, LENGTH(t.TagName) - 2)) as TagName 
               FROM STRING_SPLIT(
                   (SELECT STRING_AGG(COALESCE(p.Tags, ''), ' ') 
                    FROM Posts p 
                    WHERE p.OwnerUserId = cua.UserId AND p.PostTypeId = 1 
                    GROUP BY p.OwnerUserId), ' ') t) pt 
         WHERE pt.TagName IS NOT NULL AND pt.TagName != ''), 
        'No tags found'
    ) as UserTagString,
    
    -- Correlated subqueries
    (SELECT TOP 1 ps.Title 
     FROM UserPostAnalysis ps 
     WHERE ps.OwnerUserId = cua.UserId 
     ORDER BY ps.CreationDate DESC) as LatestPostTitle,
    
    -- Window functions on complex expressions
    LAG(cua.Reputation, 1, 0) OVER (ORDER BY cua.Reputation DESC) as PreviousReputation,
    LEAD(cua.Reputation, 1, 0) OVER (ORDER BY cua.Reputation DESC) as NextReputation,
    
    -- Complex predicates
    CASE 
        WHEN cua.Reputation > 10000 AND cua.TotalPosts > 50 THEN 'High Performance User'
        WHEN cua.Reputation BETWEEN 1000 AND 10000 AND cua.TotalPosts BETWEEN 10 AND 50 THEN 'Moderate Performance User'
        WHEN cua.Reputation < 1000 AND cua.TotalPosts < 10 THEN 'New User'
        ELSE 'User Category: Other'
    END as PerformanceCategory,
    
    -- NULL handling and conditional expressions
    ISNULL(cua.QuestionTitles, 'No questions available') as SafeQuestionTitles,
    ISNULL(cua.AnswerBodies, 'No answers available') as SafeAnswerBodies,
    
    -- String manipulations and transformations
    REPLACE(REPLACE(REPLACE(
        COALESCE(cua.QuestionTitles, ''), 
        'question', 'Question'), 
        'Answer', 'answer'), 
        'Answer', 'answer') as NormalizedQuestionTitles,
    
    -- Set operators in predicate contexts
    CASE 
        WHEN EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = cua.UserId AND p.PostTypeId = 1) 
        THEN 'Has Questions'
        ELSE 'No Questions'
    END as QuestionOwnershipStatus,
    
    -- Mathematical calculations
    ROUND((cua.TotalPosts * 1.0 / NULLIF(cua.DaysSinceRegistration, 0)) * 30, 2) as AvgPostsPerMonth,
    ROUND((cua.TotalScore * 1.0 / NULLIF(cua.TotalPosts, 0)), 2) as PointsPerPost
    
FROM ComplexUserAnalysis cua
WHERE cua.Reputation > 0 
    AND (cua.TotalPosts > 0 OR cua.TotalComments > 0 OR cua.TotalBadges > 0)
    AND cua.UserRank <= 100
    AND cua.Reputation >= (
        SELECT AVG(Reputation) FROM Users WHERE Reputation > 0
    )
ORDER BY cua.Reputation DESC, cua.TotalPosts DESC, cua.TotalScore DESC
OPTION (MAXDOP 4);
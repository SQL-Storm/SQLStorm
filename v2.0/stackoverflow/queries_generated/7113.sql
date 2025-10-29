-- {"query": "7113.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2137} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        COUNT(DISTINCT c.Id) as Comments,
        COUNT(DISTINCT b.Id) as Badges,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        RANK() OVER (ORDER BY u.Reputation DESC) as RepRank,
        NTILE(100) OVER (ORDER BY u.Reputation) as RepPercentile
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
PostPerformanceMetrics AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.LastActivityDate,
        p.OwnerUserId,
        p.PostTypeId,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END as PostTypeDesc,
        DATEDIFF(day, p.CreationDate, p.LastActivityDate) as DaysActive,
        CASE 
            WHEN p.Score >= 100 THEN 'Highly_Voted'
            WHEN p.Score >= 25 THEN 'Moderately_Voted'
            WHEN p.Score >= 0 THEN 'Neutral'
            ELSE 'Negative'
        END as ScoreCategory,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) as RankWithinUser,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as AvgScorePerUser,
        PERCENT_RANK() OVER (ORDER BY p.Score) as ScorePercentile,
        LAG(p.Score, 1) OVER (ORDER BY p.CreationDate) as PreviousScore,
        LEAD(p.AnswerCount, 1) OVER (ORDER BY p.CreationDate) as NextAnswerCount,
        NTILE(4) OVER (ORDER BY p.Score) as ScoreQuartile
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) AND p.CreationDate >= '2020-01-01'
),
UserPostMetrics AS (
    SELECT 
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.TotalPosts,
        uas.Questions,
        uas.Answers,
        uas.Comments,
        uas.Badges,
        uas.LastPostDate,
        uas.LastCommentDate,
        uas.RepRank,
        uas.RepPercentile,
        AVG(ppm.Score) as AvgPostScore,
        MAX(ppm.Score) as MaxPostScore,
        MIN(ppm.Score) as MinPostScore,
        SUM(ppm.ViewCount) as TotalViews,
        AVG(ppm.AnswerCount) as AvgAnswerCount,
        AVG(ppm.CommentCount) as AvgCommentCount,
        AVG(ppm.FavoriteCount) as AvgFavoriteCount
    FROM UserActivityStats uas
    INNER JOIN PostPerformanceMetrics ppm ON uas.UserId = ppm.OwnerUserId
    GROUP BY uas.UserId, uas.DisplayName, uas.Reputation, uas.TotalPosts, uas.Questions, uas.Answers, uas.Comments, uas.Badges, uas.LastPostDate, uas.LastCommentDate, uas.RepRank, uas.RepPercentile
),
ComplexUserAnalysis AS (
    SELECT 
        upm.UserId,
        upm.DisplayName,
        upm.Reputation,
        upm.TotalPosts,
        upm.Questions,
        upm.Answers,
        upm.Comments,
        upm.Badges,
        upm.LastPostDate,
        upm.LastCommentDate,
        upm.RepRank,
        upm.RepPercentile,
        upm.AvgPostScore,
        upm.MaxPostScore,
        upm.MinPostScore,
        upm.TotalViews,
        upm.AvgAnswerCount,
        upm.AvgCommentCount,
        upm.AvgFavoriteCount,
        CASE 
            WHEN upm.Reputation > 100000 AND upm.TotalPosts > 1000 THEN 'Legendary'
            WHEN upm.Reputation > 50000 AND upm.TotalPosts > 500 THEN 'Expert'
            WHEN upm.Reputation > 10000 AND upm.TotalPosts > 100 THEN 'Veteran'
            ELSE 'Regular'
        END as UserTier,
        CASE 
            WHEN upm.AvgPostScore > 50 THEN 'Highly_Active'
            WHEN upm.AvgPostScore > 10 THEN 'Moderately_Active'
            WHEN upm.AvgPostScore > 0 THEN 'Occasional'
            ELSE 'Inactive'
        END as ActivityLevel,
        CASE 
            WHEN upm.AvgAnswerCount > 10 THEN 'Answer_Master'
            WHEN upm.AvgAnswerCount > 5 THEN 'Answer_Specialist'
            WHEN upm.AvgAnswerCount > 0 THEN 'Answer_Enginer'
            ELSE 'Question_Focused'
        END as ContributionStyle,
        (SELECT COUNT(*) 
         FROM Posts p 
         WHERE p.OwnerUserId = upm.UserId 
         AND p.PostTypeId = 1 
         AND p.CreationDate > DATEADD(year, -1, GETDATE())) as RecentQuestions,
        (SELECT COUNT(*) 
         FROM Posts p 
         WHERE p.OwnerUserId = upm.UserId 
         AND p.PostTypeId = 2 
         AND p.CreationDate > DATEADD(year, -1, GETDATE())) as RecentAnswers,
        CASE 
            WHEN (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = upm.UserId AND p.Score > 0) > 50 THEN 'Popular'
            WHEN (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = upm.UserId AND p.Score > 0) > 10 THEN 'Notable'
            ELSE 'Average'
        END as PopularityLevel,
        DENSE_RANK() OVER (ORDER BY upm.AvgPostScore DESC) as ScoreRank,
        PERCENT_RANK() OVER (ORDER BY upm.AvgPostScore) as ScorePercentileNorm
    FROM UserPostMetrics upm
),
AggregateMetrics AS (
    SELECT 
        COUNT(*) as TotalUsers,
        AVG(Reputation) as AvgReputation,
        MAX(Reputation) as MaxReputation,
        MIN(Reputation) as MinReputation,
        AVG(TotalPosts) as AvgPosts,
        AVG(Questions) as AvgQuestions,
        AVG(Answers) as AvgAnswers,
        AVG(Comments) as AvgComments,
        AVG(Badges) as AvgBadges,
        AVG(RepPercentile) as AvgRepPercentile,
        AVG(AvgPostScore) as AvgAvgPostScore
    FROM ComplexUserAnalysis
)
SELECT 
    CASE 
        WHEN cua.Reputation > am.MaxReputation * 0.9 THEN 'Top_10%'
        WHEN cua.Reputation > am.MaxReputation * 0.75 THEN 'Top_25%'
        WHEN cua.Reputation > am.MaxReputation * 0.5 THEN 'Top_50%'
        ELSE 'Below_Median'
    END as ReputationTier,
    cua.UserTier,
    cua.ActivityLevel,
    cua.ContributionStyle,
    cua.PopularityLevel,
    cua.DisplayName,
    cua.Reputation,
    cua.TotalPosts,
    cua.Questions,
    cua.Answers,
    cua.Comments,
    cua.Badges,
    cua.AvgPostScore,
    cua.AvgAnswerCount,
    cua.AvgCommentCount,
    cua.AvgFavoriteCount,
    cua.RecentQuestions,
    cua.RecentAnswers,
    cua.ScoreRank,
    ROUND(cua.ScorePercentileNorm * 100, 2) as ScorePercentile,
    CASE 
        WHEN cua.Reputation > am.AvgReputation THEN 'Above_Avg'
        WHEN cua.Reputation < am.AvgReputation THEN 'Below_Avg'
        ELSE 'Avg'
    END as RepComparison,
    CASE 
        WHEN cua.TotalPosts > am.AvgPosts THEN 'Above_Avg_Posts'
        WHEN cua.TotalPosts < am.AvgPosts THEN 'Below_Avg_Posts'
        ELSE 'Avg_Posts'
    END as PostsComparison,
    CASE 
        WHEN cua.AvgPostScore > am.AvgAvgPostScore THEN 'Above_Avg_Score'
        WHEN cua.AvgPostScore < am.AvgAvgPostScore THEN 'Below_Avg_Score'
        ELSE 'Avg_Score'
    END as ScoreComparison,
    am.TotalUsers,
    am.AvgReputation,
    am.MaxReputation,
    am.MinReputation
FROM ComplexUserAnalysis cua
CROSS JOIN AggregateMetrics am
WHERE cua.Reputation > 1000 
AND cua.TotalPosts > 0
AND NOT (cua.Reputation = 1 AND cua.TotalPosts = 1)
AND cua.Reputation >= (SELECT AVG(Reputation) FROM Users WHERE Reputation > 0)
ORDER BY cua.Reputation DESC, cua.TotalPosts DESC, cua.AvgPostScore DESC
OFFSET 50 ROWS 
FETCH NEXT 100 ROWS ONLY;
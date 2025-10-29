-- {"query": "7219.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 4738} 
WITH UserActivityStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
        COUNT(DISTINCT c.Id) AS Comments,
        COUNT(DISTINCT b.Id) AS Badges,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(c.CreationDate) AS LastCommentDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RankByReputation,
        AVG(p.Score) AS AvgPostScore,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS MedianPostScore,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2) FILTER (WHERE p.Tags IS NOT NULL), ', ') AS AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2020-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
PostMetrics AS (
    SELECT 
        p.Id AS PostId,
        p.ParentId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.LastActivityDate,
        p.Title,
        p.Tags,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN 'HasAnswers'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Question'
        END AS PostCategory,
        DATEDIFF(day, p.CreationDate, p.LastActivityDate) AS DaysActive,
        COALESCE(p.ViewCount, 0) + COALESCE(p.AnswerCount, 0) + COALESCE(p.CommentCount, 0) AS EngagementScore,
        NTILE(4) OVER (ORDER BY p.Score DESC) AS ScoreQuartile,
        CASE 
            WHEN p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'AboveAverage'
            ELSE 'BelowAverage'
        END AS ScorePerformance,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS RankByType
    FROM Posts p
    WHERE p.CreationDate >= '2020-01-01'
),
UserPostActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(p.Id) AS PostsCreated,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionsCreated,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswersCreated,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalQuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS AvgAnswerScore,
        COUNT(DISTINCT p.Tags) AS UniqueTagsUsed,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2) FILTER (WHERE p.Tags IS NOT NULL), '; ') AS TagsUsed,
        MAX(p.CreationDate) AS LastActivity,
        MIN(p.CreationDate) AS FirstActivity
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate >= '2020-01-01'
    GROUP BY u.Id, u.DisplayName
),
ComplexPostAnalysis AS (
    SELECT 
        p.PostId,
        p.ParentId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.LastActivityDate,
        p.Title,
        p.Tags,
        p.PostCategory,
        p.DaysActive,
        p.EngagementScore,
        p.ScoreQuartile,
        p.ScorePerformance,
        p.RankByType,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AnswerCount = 0 THEN 'Unanswered'
            WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 AND p.Score < 0 THEN 'AnsweredButDownvoted'
            WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 AND p.Score > 0 THEN 'AnsweredAndUpvoted'
            WHEN p.PostTypeId = 2 AND p.Score > 0 THEN 'AnswerUpvoted'
            WHEN p.PostTypeId = 2 AND p.Score < 0 THEN 'AnswerDownvoted'
            ELSE 'Other'
        END AS QualityIndicator,
        CASE 
            WHEN p.PostTypeId = 1 THEN 
                CASE 
                    WHEN p.AnswerCount > 0 THEN 
                        CASE 
                            WHEN p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) 
                            THEN (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 1 AND OwnerUserId = (
                                SELECT OwnerUserId FROM Posts WHERE Id = p.PostId
                            )) * p.Score / p.AnswerCount
                            ELSE (p.Score * p.AnswerCount) / (
                                SELECT COUNT(*) FROM Posts WHERE PostTypeId = 2 AND ParentId = p.PostId
                            ) * 0.75
                        END
                    ELSE p.Score * 1.5
                END
            ELSE p.Score
        END AS WeightedScore,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS TopScoreRank,
        DENSE_RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.ViewCount DESC) AS TopViewRank,
        NTILE(5) OVER (ORDER BY p.ViewCount) AS ViewPerformanceBracket
    FROM PostMetrics p
    WHERE p.CreationDate >= '2020-01-01'
),
CombinedUserStats AS (
    SELECT 
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.Views,
        uas.UpVotes,
        uas.DownVotes,
        uas.TotalPosts,
        uas.Questions,
        uas.Answers,
        uas.Comments,
        uas.Badges,
        uas.LastPostDate,
        uas.LastCommentDate,
        uas.RankByReputation,
        uas.AvgPostScore,
        uas.MedianPostScore,
        uas.AllTags,
        upa.PostsCreated,
        upa.QuestionsCreated,
        upa.AnswersCreated,
        upa.TotalQuestionScore,
        upa.TotalAnswerScore,
        upa.AvgQuestionScore,
        upa.AvgAnswerScore,
        upa.UniqueTagsUsed,
        upa.TagsUsed,
        upa.LastActivity,
        upa.FirstActivity,
        CASE 
            WHEN upa.PostsCreated > 0 THEN
                (upa.QuestionsCreated * 100.0 / upa.PostsCreated)
            ELSE 0 
        END AS QuestionPercentage,
        CASE 
            WHEN uas.TotalPosts > 0 THEN
                (upa.AnswersCreated * 100.0 / uas.TotalPosts)
            ELSE 0 
        END AS AnswerPercentage,
        (upa.TotalQuestionScore + upa.TotalAnswerScore) AS TotalScore,
        (upa.UniqueTagsUsed * 10) AS TagComplexityScore
    FROM UserActivityStats uas
    INNER JOIN UserPostActivity upa ON uas.UserId = upa.UserId
    WHERE uas.UserId IN (
        SELECT DISTINCT OwnerUserId FROM Posts WHERE CreationDate >= '2020-01-01'
        UNION
        SELECT DISTINCT UserId FROM Comments WHERE CreationDate >= '2020-01-01'
        UNION 
        SELECT DISTINCT UserId FROM Badges WHERE Date >= '2020-01-01'
    )
),
PerformanceBaseline AS (
    SELECT 
        'HighEngagement' AS Category,
        COUNT(*) AS Count,
        AVG(Reputation) AS AvgReputation,
        MIN(Reputation) AS MinReputation,
        MAX(Reputation) AS MaxReputation,
        AVG(TotalPosts) AS AvgPosts,
        AVG(Questions) AS AvgQuestions,
        AVG(Answers) AS AvgAnswers,
        AVG(Comments) AS AvgComments,
        AVG(Badges) AS AvgBadges
    FROM CombinedUserStats cus
    WHERE cus.TotalPosts > 100
    GROUP BY 'HighEngagement'
    HAVING COUNT(*) > 5
    UNION ALL
    SELECT 
        'MediumEngagement' AS Category,
        COUNT(*) AS Count,
        AVG(Reputation) AS AvgReputation,
        MIN(Reputation) AS MinReputation,
        MAX(Reputation) AS MaxReputation,
        AVG(TotalPosts) AS AvgPosts,
        AVG(Questions) AS AvgQuestions,
        AVG(Answers) AS AvgAnswers,
        AVG(Comments) AS AvgComments,
        AVG(Badges) AS AvgBadges
    FROM CombinedUserStats cus
    WHERE cus.TotalPosts BETWEEN 10 AND 100
    GROUP BY 'MediumEngagement'
    HAVING COUNT(*) > 5
    UNION ALL
    SELECT 
        'LowEngagement' AS Category,
        COUNT(*) AS Count,
        AVG(Reputation) AS AvgReputation,
        MIN(Reputation) AS MinReputation,
        MAX(Reputation) AS MaxReputation,
        AVG(TotalPosts) AS AvgPosts,
        AVG(Questions) AS AvgQuestions,
        AVG(Answers) AS AvgAnswers,
        AVG(Comments) AS AvgComments,
        AVG(Badges) AS AvgBadges
    FROM CombinedUserStats cus
    WHERE cus.TotalPosts < 10
    GROUP BY 'LowEngagement'
    HAVING COUNT(*) > 5
),
TopPerformerAnalysis AS (
    SELECT 
        cua.UserId,
        cua.DisplayName,
        cua.Reputation,
        cua.TotalPosts,
        cua.Questions,
        cua.Answers,
        cua.Comments,
        cua.Badges,
        cua.TotalScore,
        cua.TagComplexityScore,
        CASE 
            WHEN cua.Questions > 0 THEN
                (cua.TotalQuestionScore * 1.0 / cua.Questions)
            ELSE NULL 
        END AS AvgQuestionScorePerQuestion,
        CASE 
            WHEN cua.Answers > 0 THEN
                (cua.TotalAnswerScore * 1.0 / cua.Answers)
            ELSE NULL 
        END AS AvgAnswerScorePerAnswer,
        DENSE_RANK() OVER (ORDER BY cua.TotalScore DESC) AS ScoreRank,
        DENSE_RANK() OVER (ORDER BY cua.TagComplexityScore DESC) AS ComplexityRank,
        cua.QuestionPercentage,
        cua.AnswerPercentage,
        DENSE_RANK() OVER (ORDER BY (cua.TotalScore + cua.TagComplexityScore) DESC) AS CompositeRank,
        CONCAT(
            'User: ', cua.DisplayName, 
            ' - Score: ', cua.TotalScore, 
            ' - Complexity: ', cua.TagComplexityScore,
            ' - Q%: ', ROUND(cua.QuestionPercentage, 2),
            ' - A%: ', ROUND(cua.AnswerPercentage, 2)
        ) AS UserPerformanceSummary
    FROM CombinedUserStats cua
    WHERE cua.TotalPosts > 0
),
FinalAnalysis AS (
    SELECT 
        tpa.UserId,
        tpa.DisplayName,
        tpa.Reputation,
        tpa.TotalPosts,
        tpa.Questions,
        tpa.Answers,
        tpa.Comments,
        tpa.Badges,
        tpa.TotalScore,
        tpa.TagComplexityScore,
        tpa.AvgQuestionScorePerQuestion,
        tpa.AvgAnswerScorePerAnswer,
        tpa.ScoreRank,
        tpa.ComplexityRank,
        tpa.QuestionPercentage,
        tpa.AnswerPercentage,
        tpa.CompositeRank,
        tpa.UserPerformanceSummary,
        CASE 
            WHEN tpa.CompositeRank <= (SELECT COUNT(*) FROM TopPerformerAnalysis) * 0.1 THEN 'Top10%'
            WHEN tpa.CompositeRank <= (SELECT COUNT(*) FROM TopPerformerAnalysis) * 0.25 THEN 'Top25%'
            WHEN tpa.CompositeRank <= (SELECT COUNT(*) FROM TopPerformerAnalysis) * 0.5 THEN 'Top50%'
            ELSE 'Below50%'
        END AS PerformanceTier,
        CASE 
            WHEN tpa.CompositeRank <= (SELECT COUNT(*) FROM TopPerformerAnalysis) * 0.1 THEN 1
            WHEN tpa.CompositeRank <= (SELECT COUNT(*) FROM TopPerformerAnalysis) * 0.25 THEN 2
            WHEN tpa.CompositeRank <= (SELECT COUNT(*) FROM TopPerformerAnalysis) * 0.5 THEN 3
            ELSE 4
        END AS PerformanceLevel,
        (SELECT COUNT(*) FROM CombinedUserStats WHERE Reputation > tpa.Reputation) AS UsersAboveInReputation,
        (SELECT COUNT(*) FROM CombinedUserStats WHERE TotalPosts > tpa.TotalPosts) AS UsersAboveInPosts,
        (SELECT AVG(Reputation) FROM CombinedUserStats WHERE TotalPosts > 0) AS OverallAvgReputation,
        (SELECT AVG(TotalPosts) FROM CombinedUserStats WHERE TotalPosts > 0) AS OverallAvgPosts
    FROM TopPerformerAnalysis tpa
),
PostComplexityAnalysis AS (
    SELECT 
        ca.PostId,
        ca.ParentId,
        ca.PostTypeId,
        ca.Score,
        ca.ViewCount,
        ca.AnswerCount,
        ca.CommentCount,
        ca.FavoriteCount,
        ca.CreationDate,
        ca.LastActivityDate,
        ca.Title,
        ca.Tags,
        ca.PostCategory,
        ca.DaysActive,
        ca.EngagementScore,
        ca.ScoreQuartile,
        ca.ScorePerformance,
        ca.RankByType,
        ca.QualityIndicator,
        ca.WeightedScore,
        ca.TopScoreRank,
        ca.TopViewRank,
        ca.ViewPerformanceBracket,
        CASE 
            WHEN ca.AnswerCount IS NOT NULL AND ca.AnswerCount > 0 THEN 
                (CASE 
                    WHEN ca.AnswerCount > (SELECT AVG(AnswerCount) FROM Posts WHERE PostTypeId = 1) 
                    THEN 'HighAnswerCount' 
                    ELSE 'NormalAnswerCount' 
                END)
            ELSE 'NoAnswers' 
        END AS AnswerComplexity,
        CASE 
            WHEN ca.Tags IS NOT NULL AND LENGTH(ca.Tags) > 0 THEN 
                (CASE 
                    WHEN LENGTH(ca.Tags) > 50 THEN 'HighTagDensity' 
                    ELSE 'NormalTagDensity' 
                END)
            ELSE 'NoTags' 
        END AS TagComplexity,
        CASE 
            WHEN ca.Score > 5 AND ca.ViewCount > 200 THEN 'PopularHighScore'
            WHEN ca.Score <= 5 AND ca.ViewCount < 50 THEN 'LowActivity'
            ELSE 'StandardActivity'
        END AS ActivityLevel,
        CASE 
            WHEN ca.ViewPerformanceBracket = 1 THEN 'HighestViewed'
            WHEN ca.ViewPerformanceBracket <= 2 THEN 'HighViewed'
            WHEN ca.ViewPerformanceBracket = 5 THEN 'LowestViewed'
            ELSE 'MidViewed'
        END AS ViewPerformanceLevel
    FROM ComplexPostAnalysis ca
    WHERE ca.CreationDate >= '2020-01-01'
)
SELECT 
    fa.UserId,
    fa.DisplayName,
    fa.Reputation,
    fa.TotalPosts,
    fa.Questions,
    fa.Answers,
    fa.Comments,
    fa.Badges,
    fa.TotalScore,
    fa.TagComplexityScore,
    fa.AvgQuestionScorePerQuestion,
    fa.AvgAnswerScorePerAnswer,
    fa.ScoreRank,
    fa.ComplexityRank,
    fa.QuestionPercentage,
    fa.AnswerPercentage,
    fa.CompositeRank,
    fa.PerformanceTier,
    fa.PerformanceLevel,
    fa.UsersAboveInReputation,
    fa.UsersAboveInPosts,
    fa.OverallAvgReputation,
    fa.OverallAvgPosts,
    ppa.PostId,
    ppa.ParentId,
    ppa.PostTypeId,
    ppa.Score,
    ppa.ViewCount,
    ppa.AnswerCount,
    ppa.CommentCount,
    ppa.FavoriteCount,
    ppa.CreationDate,
    ppa.LastActivityDate,
    ppa.Title,
    ppa.Tags,
    ppa.PostCategory,
    ppa.DaysActive,
    ppa.EngagementScore,
    ppa.ScoreQuartile,
    ppa.ScorePerformance,
    ppa.RankByType,
    ppa.QualityIndicator,
    ppa.WeightedScore,
    ppa.TopScoreRank,
    ppa.TopViewRank,
    ppa.ViewPerformanceBracket,
    ppa.AnswerComplexity,
    ppa.TagComplexity,
    ppa.ActivityLevel,
    ppa.ViewPerformanceLevel,
    (SELECT COUNT(*) FROM CombinedUserStats) AS TotalActiveUsers,
    (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 1) AS TotalQuestions,
    (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 2) AS TotalAnswers,
    (SELECT COUNT(*) FROM Posts WHERE CreationDate >= '2020-01-01') AS RecentPosts,
    (SELECT COUNT(*) FROM Users WHERE CreationDate >= '2020-01-01') AS RecentUsers,
    CASE 
        WHEN fa.Reputation > (SELECT AVG(Reputation) FROM Users) 
             AND fa.TotalPosts > (SELECT AVG(TotalPosts) FROM CombinedUserStats) 
             AND fa.TagComplexityScore > 100 
        THEN 'EliteActive'
        WHEN fa.Reputation > (SELECT AVG(Reputation) FROM Users) 
             AND fa.TotalPosts > (SELECT AVG(TotalPosts) FROM CombinedUserStats) 
        THEN 'Active'
        WHEN fa.Reputation > 500 
        THEN 'Regular'
        ELSE 'Casual'
    END AS UserProfile,
    CASE 
        WHEN ppa.ViewPerformanceLevel IN ('HighestViewed', 'HighViewed') 
        THEN 'HighVisibility'
        WHEN ppa.ViewPerformanceLevel IN ('LowestViewed', 'LowViewed') 
        THEN 'LowVisibility'
        ELSE 'ModerateVisibility'
    END AS VisibilityCategory,
    (SELECT STRING_AGG(CONCAT(' ', pp.PostCategory, ': ', pp.Score), ', ') 
     FROM PostMetrics pp 
     WHERE pp.PostId IN (SELECT PostId FROM ComplexPostAnalysis WHERE ViewPerformanceBracket <= 2 AND ScoreQuartile = 4)
    ) AS HighPerformingPosts,
    (SELECT CONCAT('Reputation: ', AVG(Reputation), ' Posts: ', AVG(TotalPosts)) 
     FROM CombinedUserStats 
     WHERE CompositeRank <= (SELECT COUNT(*) FROM TopPerformerAnalysis) * 0.1
    ) AS TopPerformerBaseline,
    (SELECT COUNT(*) FROM PerformanceBaseline) AS BaselineCategoriesCount,
    (SELECT MAX(Count) FROM PerformanceBaseline) AS MaxBaselineCount,
    (SELECT SUM(Count) FROM PerformanceBaseline WHERE Category = 'HighEngagement') AS HighEngagementCount,
    (SELECT SUM(Count) FROM PerformanceBaseline WHERE Category = 'MediumEngagement') AS MediumEngagementCount,
    (SELECT SUM(Count) FROM PerformanceBaseline WHERE Category = 'LowEngagement') AS LowEngagementCount,
    CONCAT(
        fa.DisplayName, 
        ' - Rank: ', fa.CompositeRank, 
        ' - Level: ', fa.PerformanceLevel,
        ' - Posts: ', fa.TotalPosts,
        ' - Score: ', fa.TotalScore,
        ' - Comp: ', fa.TagComplexityScore,
        ' - Q: ', ROUND(fa.QuestionPercentage, 1),
        ' - A: ', ROUND(fa.AnswerPercentage, 1)
    ) AS FullPerformanceSummary
FROM FinalAnalysis fa
INNER JOIN PostComplexityAnalysis ppa ON fa.UserId IN (
    SELECT OwnerUserId FROM Posts WHERE Id = ppa.PostId AND ParentId IS NULL
)
WHERE fa.CompositeRank <= 100
GROUP BY 
    fa.UserId, fa.DisplayName, fa.Reputation, fa.TotalPosts, fa.Questions, fa.Answers, 
    fa.Comments, fa.Badges, fa.TotalScore, fa.TagComplexityScore, fa.AvgQuestionScorePerQuestion,
    fa.AvgAnswerScorePerAnswer, fa.ScoreRank, fa.ComplexityRank, fa.QuestionPercentage,
    fa.AnswerPercentage, fa.CompositeRank, fa.PerformanceTier, fa.PerformanceLevel,
    fa.UsersAboveInReputation, fa.UsersAboveInPosts, fa.OverallAvgReputation,
    fa.OverallAvgPosts, ppa.PostId, ppa.ParentId, ppa.PostTypeId, ppa.Score, ppa.ViewCount,
    ppa.AnswerCount, ppa.CommentCount, ppa.FavoriteCount, ppa.CreationDate,
    ppa.LastActivityDate, ppa.Title, ppa.Tags, ppa.PostCategory, ppa.DaysActive,
    ppa.EngagementScore, ppa.ScoreQuartile, ppa.ScorePerformance, ppa.RankByType,
    ppa.QualityIndicator, ppa.WeightedScore, ppa.TopScoreRank, ppa.TopViewRank,
    ppa.ViewPerformanceBracket, ppa.AnswerComplexity, ppa.TagComplexity,
    ppa.ActivityLevel, ppa.ViewPerformanceLevel
HAVING COUNT(*) > 0
ORDER BY fa.CompositeRank ASC
LIMIT 500;
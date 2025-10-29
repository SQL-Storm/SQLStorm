-- {"query": "7888.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 3444} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        COUNT(DISTINCT c.Id) as Comments,
        COUNT(DISTINCT b.Id) as Badges,
        COUNT(DISTINCT v.Id) as Votes,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        MAX(v.CreationDate) as LastVoteDate,
        DATEDIFF(day, u.CreationDate, GETDATE()) as AccountAgeDays,
        DATEDIFF(day, COALESCE(MAX(p.CreationDate), u.CreationDate), GETDATE()) as ActiveDays,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        COALESCE(SUM(p.ViewCount), 0) as TotalViews,
        COALESCE(SUM(p.AnswerCount), 0) as TotalAnswers,
        COALESCE(SUM(p.CommentCount), 0) as TotalComments
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.CreationDate
),
PostComplexityAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.OwnerUserId,
        p.ParentId,
        COALESCE(p.Tags, '') as Tags,
        CASE 
            WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN 
                (LEN(p.Tags) - LEN(REPLACE(p.Tags, '><', '')) + 1)
            ELSE 0 
        END as TagCount,
        CASE 
            WHEN p.Body IS NOT NULL AND LEN(p.Body) > 0 THEN 
                (LEN(p.Body) - LEN(REPLACE(p.Body, '<', '')) + 1)
            ELSE 0 
        END as HtmlTagCount,
        CASE 
            WHEN p.Body IS NOT NULL THEN 
                (LEN(p.Body) - LEN(REPLACE(p.Body, ' ', '')) + 1)
            ELSE 0 
        END as WordCount,
        IIF(p.Score > 100, 'High', IIF(p.Score > 10, 'Medium', 'Low')) as ScoreCategory,
        IIF(p.AnswerCount > 5, 'High', IIF(p.AnswerCount > 1, 'Medium', 'Low')) as AnswerCategory,
        IIF(p.CommentCount > 5, 'High', IIF(p.CommentCount > 1, 'Medium', 'Low')) as CommentCategory
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) -- Only questions and answers
),
UserPostPerformance AS (
    SELECT 
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.TotalPosts,
        uas.Questions,
        uas.Answers,
        uas.Comments,
        uas.Badges,
        uas.Votes,
        uas.LastPostDate,
        uas.LastCommentDate,
        uas.LastVoteDate,
        uas.AccountAgeDays,
        uas.ActiveDays,
        uas.TotalScore,
        uas.TotalViews,
        uas.TotalAnswers,
        uas.TotalComments,
        CASE 
            WHEN uas.TotalPosts > 0 THEN 
                CAST(uas.TotalScore AS FLOAT) / CAST(uas.TotalPosts AS FLOAT)
            ELSE 0 
        END as AvgScorePerPost,
        CASE 
            WHEN uas.TotalPosts > 0 THEN 
                CAST(uas.TotalViews AS FLOAT) / CAST(uas.TotalPosts AS FLOAT)
            ELSE 0 
        END as AvgViewsPerPost,
        CASE 
            WHEN uas.TotalAnswers > 0 THEN 
                CAST(uas.TotalComments AS FLOAT) / CAST(uas.TotalAnswers AS FLOAT)
            ELSE 0 
        END as AvgCommentsPerAnswer,
        CASE 
            WHEN uas.TotalPosts > 0 THEN 
                CAST(uas.TotalVotes AS FLOAT) / CAST(uas.TotalPosts AS FLOAT)
            ELSE 0 
        END as AvgVotesPerPost,
        ROW_NUMBER() OVER (ORDER BY uas.TotalScore DESC) as ScoreRank,
        RANK() OVER (ORDER BY uas.TotalViews DESC) as ViewRank,
        DENSE_RANK() OVER (ORDER BY uas.Reputation DESC) as RepRank
    FROM UserActivityStats uas
),
TopUsers WITH (NOLOCK) AS (
    SELECT 
        upp.UserId,
        upp.DisplayName,
        upp.Reputation,
        upp.TotalPosts,
        upp.Questions,
        upp.Answers,
        upp.Comments,
        upp.Badges,
        upp.Votes,
        upp.LastPostDate,
        upp.LastCommentDate,
        upp.LastVoteDate,
        upp.AccountAgeDays,
        upp.ActiveDays,
        upp.TotalScore,
        upp.TotalViews,
        upp.TotalAnswers,
        upp.TotalComments,
        upp.AvgScorePerPost,
        upp.AvgViewsPerPost,
        upp.AvgCommentsPerAnswer,
        upp.AvgVotesPerPost,
        upp.ScoreRank,
        upp.ViewRank,
        upp.RepRank,
        CASE 
            WHEN upp.Reputation > 10000 THEN 'Elite'
            WHEN upp.Reputation > 5000 THEN 'Veteran'
            WHEN upp.Reputation > 1000 THEN 'Expert'
            ELSE 'Regular'
        END as RepTier,
        CASE 
            WHEN upp.TotalPosts > 1000 THEN 'Master'
            WHEN upp.TotalPosts > 500 THEN 'Expert'
            WHEN upp.TotalPosts > 100 THEN 'Novice'
            ELSE 'Beginner'
        END as ActivityTier
    FROM UserPostPerformance upp
    WHERE upp.Reputation > 100
),
PostAnalysisSummary AS (
    SELECT 
        pca.PostId,
        pca.Title,
        pca.PostTypeId,
        pca.Score,
        pca.ViewCount,
        pca.AnswerCount,
        pca.CommentCount,
        pca.FavoriteCount,
        pca.CreationDate,
        pca.OwnerUserId,
        pca.ParentId,
        pca.Tags,
        pca.TagCount,
        pca.HtmlTagCount,
        pca.WordCount,
        pca.ScoreCategory,
        pca.AnswerCategory,
        pca.CommentCategory,
        CASE 
            WHEN pca.TagCount > 3 THEN 'Heavy Tagged'
            WHEN pca.TagCount > 1 THEN 'Moderately Tagged'
            ELSE 'Lightly Tagged'
        END as TagIntensity,
        CASE 
            WHEN pca.WordCount > 500 THEN 'Very Long'
            WHEN pca.WordCount > 200 THEN 'Long'
            WHEN pca.WordCount > 50 THEN 'Medium'
            ELSE 'Short'
        END as PostLength
    FROM PostComplexityAnalysis pca
),
CombinedAnalysis AS (
    SELECT 
        tu.UserId,
        tu.DisplayName,
        tu.Reputation,
        tu.TotalPosts,
        tu.Questions,
        tu.Answers,
        tu.Comments,
        tu.Badges,
        tu.Votes,
        tu.AccountAgeDays,
        tu.ActiveDays,
        tu.TotalScore,
        tu.TotalViews,
        tu.TotalAnswers,
        tu.TotalComments,
        tu.AvgScorePerPost,
        tu.AvgViewsPerPost,
        tu.AvgCommentsPerAnswer,
        tu.AvgVotesPerPost,
        tu.ScoreRank,
        tu.ViewRank,
        tu.RepRank,
        tu.RepTier,
        tu.ActivityTier,
        pa.PostId,
        pa.Title,
        pa.PostTypeId,
        pa.Score,
        pa.ViewCount,
        pa.AnswerCount,
        pa.CommentCount,
        pa.FavoriteCount,
        pa.CreationDate,
        pa.OwnerUserId,
        pa.ParentId,
        pa.Tags,
        pa.TagCount,
        pa.HtmlTagCount,
        pa.WordCount,
        pa.ScoreCategory,
        pa.AnswerCategory,
        pa.CommentCategory,
        pa.TagIntensity,
        pa.PostLength,
        DATEDIFF(day, pa.CreationDate, GETDATE()) as PostAgeDays,
        CASE 
            WHEN pa.PostTypeId = 1 THEN 'Question'
            WHEN pa.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostType
    FROM TopUsers tu
    JOIN PostAnalysisSummary pa ON tu.UserId = pa.OwnerUserId
),
ComplexPostAnalysis AS (
    SELECT 
        ca.UserId,
        ca.DisplayName,
        ca.Reputation,
        ca.TotalPosts,
        ca.Questions,
        ca.Answers,
        ca.Comments,
        ca.Badges,
        ca.Votes,
        ca.AccountAgeDays,
        ca.ActiveDays,
        ca.TotalScore,
        ca.TotalViews,
        ca.TotalAnswers,
        ca.TotalComments,
        ca.AvgScorePerPost,
        ca.AvgViewsPerPost,
        ca.AvgCommentsPerAnswer,
        ca.AvgVotesPerPost,
        ca.ScoreRank,
        ca.ViewRank,
        ca.RepRank,
        ca.RepTier,
        ca.ActivityTier,
        ca.PostId,
        ca.Title,
        ca.PostTypeId,
        ca.Score,
        ca.ViewCount,
        ca.AnswerCount,
        ca.CommentCount,
        ca.FavoriteCount,
        ca.CreationDate,
        ca.ParentId,
        ca.Tags,
        ca.TagCount,
        ca.HtmlTagCount,
        ca.WordCount,
        ca.ScoreCategory,
        ca.AnswerCategory,
        ca.CommentCategory,
        ca.TagIntensity,
        ca.PostLength,
        ca.PostAgeDays,
        ca.PostType,
        CASE 
            WHEN ca.TagCount > 0 AND ca.WordCount > 50 THEN 
                CAST(ca.WordCount AS FLOAT) / CAST(ca.TagCount AS FLOAT)
            ELSE 0 
        END as WordsPerTag,
        CASE 
            WHEN ca.ViewCount > 0 THEN 
                CAST(ca.Score AS FLOAT) / CAST(ca.ViewCount AS FLOAT)
            ELSE 0 
        END as ScorePerView,
        CASE 
            WHEN ca.AnswerCount > 0 THEN 
                CAST(ca.CommentCount AS FLOAT) / CAST(ca.AnswerCount AS FLOAT)
            ELSE 0 
        END as CommentsPerAnswer,
        CASE 
            WHEN ca.PostAgeDays > 0 THEN 
                CAST(ca.ViewCount AS FLOAT) / CAST(ca.PostAgeDays AS FLOAT)
            ELSE 0 
        END as DailyViews,
        ROW_NUMBER() OVER (PARTITION BY ca.PostTypeId ORDER BY ca.Score DESC) as ScoreRankPerType
    FROM CombinedAnalysis ca
    WHERE ca.PostAgeDays > 30 AND ca.Score > 0
),
FinalAggregatedData AS (
    SELECT 
        cpa.UserId,
        cpa.DisplayName,
        cpa.Reputation,
        cpa.TotalPosts,
        cpa.Questions,
        cpa.Answers,
        cpa.Comments,
        cpa.Badges,
        cpa.Votes,
        cpa.AccountAgeDays,
        cpa.ActiveDays,
        cpa.TotalScore,
        cpa.TotalViews,
        cpa.TotalAnswers,
        cpa.TotalComments,
        cpa.AvgScorePerPost,
        cpa.AvgViewsPerPost,
        cpa.AvgCommentsPerAnswer,
        cpa.AvgVotesPerPost,
        cpa.ScoreRank,
        cpa.ViewRank,
        cpa.RepRank,
        cpa.RepTier,
        cpa.ActivityTier,
        cpa.PostId,
        cpa.Title,
        cpa.PostTypeId,
        cpa.Score,
        cpa.ViewCount,
        cpa.AnswerCount,
        cpa.CommentCount,
        cpa.FavoriteCount,
        cpa.CreationDate,
        cpa.ParentId,
        cpa.Tags,
        cpa.TagCount,
        cpa.HtmlTagCount,
        cpa.WordCount,
        cpa.ScoreCategory,
        cpa.AnswerCategory,
        cpa.CommentCategory,
        cpa.TagIntensity,
        cpa.PostLength,
        cpa.PostAgeDays,
        cpa.PostType,
        cpa.WordsPerTag,
        cpa.ScorePerView,
        cpa.CommentsPerAnswer,
        cpa.DailyViews,
        cpa.ScoreRankPerType,
        CASE 
            WHEN cpa.PostTypeId = 1 AND cpa.AnswerCount > 0 THEN 'QuestionWithAnswers'
            WHEN cpa.PostTypeId = 2 AND cpa.ParentId IS NOT NULL THEN 'AnswerToQuestion'
            ELSE 'Other'
        END as PostClassification,
        CASE 
            WHEN cpa.RepTier = 'Elite' AND cpa.ScoreCategory = 'High' THEN 'EliteHighPerforming'
            WHEN cpa.RepTier = 'Veteran' AND cpa.ViewCount > 1000 THEN 'VeteranHighReach'
            WHEN cpa.ActivityTier = 'Master' AND cpa.AnswerCount > 10 THEN 'MasterAnswerer'
            ELSE 'Standard'
        END as UserPostPerformanceCategory,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = cpa.UserId AND p.PostTypeId = 1) as UserQuestionCount,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = cpa.UserId AND p.PostTypeId = 2) as UserAnswerCount
    FROM ComplexPostAnalysis cpa
)
SELECT 
    fd.UserId,
    fd.DisplayName,
    fd.Reputation,
    fd.TotalPosts,
    fd.Questions,
    fd.Answers,
    fd.Comments,
    fd.Badges,
    fd.Votes,
    fd.AccountAgeDays,
    fd.ActiveDays,
    fd.TotalScore,
    fd.TotalViews,
    fd.TotalAnswers,
    fd.TotalComments,
    fd.AvgScorePerPost,
    fd.AvgViewsPerPost,
    fd.AvgCommentsPerAnswer,
    fd.AvgVotesPerPost,
    fd.ScoreRank,
    fd.ViewRank,
    fd.RepRank,
    fd.RepTier,
    fd.ActivityTier,
    fd.PostId,
    fd.Title,
    fd.PostTypeId,
    fd.Score,
    fd.ViewCount,
    fd.AnswerCount,
    fd.CommentCount,
    fd.FavoriteCount,
    fd.CreationDate,
    fd.ParentId,
    fd.Tags,
    fd.TagCount,
    fd.HtmlTagCount,
    fd.WordCount,
    fd.ScoreCategory,
    fd.AnswerCategory,
    fd.CommentCategory,
    fd.TagIntensity,
    fd.PostLength,
    fd.PostAgeDays,
    fd.PostType,
    fd.WordsPerTag,
    fd.ScorePerView,
    fd.CommentsPerAnswer,
    fd.DailyViews,
    fd.ScoreRankPerType,
    fd.PostClassification,
    fd.UserPostPerformanceCategory,
    fd.UserQuestionCount,
    fd.UserAnswerCount,
    CASE 
        WHEN fd.Reputation < 1000 THEN 'Poor'
        WHEN fd.Reputation BETWEEN 1000 AND 5000 THEN 'Fair'
        WHEN fd.Reputation BETWEEN 5000 AND 10000 THEN 'Good'
        WHEN fd.Reputation BETWEEN 10000 AND 50000 THEN 'Excellent'
        ELSE 'Outstanding'
    END as RepPerformance
FROM FinalAggregatedData fd
WHERE fd.TotalScore > 100 
    AND fd.TotalViews > 100
    AND fd.AnswerCount > 0
    AND fd.PostAgeDays BETWEEN 30 AND 365
    AND (fd.RepTier IN ('Elite', 'Veteran') OR fd.ActivityTier IN ('Master', 'Expert'))
    AND (fd.PostClassification LIKE '%Question%' OR fd.PostClassification LIKE '%Answer%')
ORDER BY fd.Score DESC, fd.Reputation DESC, fd.TotalViews DESC
OFFSET 1000 ROWS
FETCH NEXT 1000 ROWS ONLY;
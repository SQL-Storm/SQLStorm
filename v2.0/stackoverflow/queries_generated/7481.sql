-- {"query": "7481.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 3671} 
WITH PostStats AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
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
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostType,
        COALESCE(p.ViewCount, 0) + COALESCE(p.AnswerCount, 0) + COALESCE(p.CommentCount, 0) as ActivityScore,
        DATEDIFF('day', p.CreationDate, p.LastActivityDate) as DaysSinceCreation,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as UserPostRank,
        RANK() OVER (ORDER BY p.Score DESC) as ScoreRank,
        PERCENT_RANK() OVER (ORDER BY p.Score) as ScorePercentile,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as AvgScorePerUser,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) as TotalPostsPerUser,
        CASE 
            WHEN p.PostTypeId = 1 AND p.ParentId IS NULL THEN 1
            ELSE 0
        END as IsQuestion,
        CASE 
            WHEN p.PostTypeId = 2 AND p.ParentId IS NOT NULL THEN 1
            ELSE 0
        END as IsAnswer,
        CASE 
            WHEN p.CommentCount > 0 THEN 1
            ELSE 0
        END as HasComments,
        CASE 
            WHEN p.AnswerCount > 0 THEN 1
            ELSE 0
        END as HasAnswers,
        CASE 
            WHEN p.FavoriteCount > 0 THEN 1
            ELSE 0
        END as IsBookmarked,
        CASE 
            WHEN p.Score > 100 THEN 'High'
            WHEN p.Score > 10 THEN 'Medium'
            ELSE 'Low'
        END as ScoreCategory,
        LAG(p.Score, 1) OVER (ORDER BY p.CreationDate) as PreviousScore,
        LEAD(p.Score, 1) OVER (ORDER BY p.CreationDate) as NextScore,
        NTILE(10) OVER (ORDER BY p.Score) as ScoreDecile,
        COALESCE(p.Tags, '') as CleanTags,
        LENGTH(COALESCE(p.Tags, '')) as TagsLength,
        CASE 
            WHEN LENGTH(COALESCE(p.Tags, '')) > 0 THEN 1
            ELSE 0
        END as HasTags,
        COALESCE(TRIM(BOTH '<>' FROM COALESCE(p.Tags, '')), '') as TrimmedTags
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserActivity AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.AccountId,
        COALESCE(SUM(ps.Score), 0) as TotalScore,
        COALESCE(COUNT(ps.Id), 0) as TotalPosts,
        COALESCE(SUM(ps.ViewCount), 0) as TotalViews,
        COALESCE(SUM(ps.AnswerCount), 0) as TotalAnswers,
        COALESCE(SUM(ps.CommentCount), 0) as TotalComments,
        COALESCE(SUM(ps.FavoriteCount), 0) as TotalFavorites,
        AVG(ps.Score) as AvgScore,
        MAX(ps.CreationDate) as LastPostDate,
        MIN(ps.CreationDate) as FirstPostDate,
        DATEDIFF('day', MIN(ps.CreationDate), MAX(ps.CreationDate)) as DaysActive,
        ROUND(AVG(ps.Score), 2) as AvgPostScore,
        ROUND(SUM(ps.ViewCount) * 1.0 / NULLIF(COUNT(ps.Id), 0), 2) as AvgViewsPerPost,
        ROW_NUMBER() OVER (ORDER BY COALESCE(SUM(ps.Score), 0) DESC) as UserRank,
        RANK() OVER (ORDER BY u.Reputation DESC) as ReputationRank,
        CASE 
            WHEN COALESCE(SUM(ps.Score), 0) > 1000 THEN 'Veteran'
            WHEN COALESCE(SUM(ps.Score), 0) > 100 THEN 'Experienced'
            WHEN COALESCE(SUM(ps.Score), 0) > 0 THEN 'Active'
            ELSE 'New'
        END as UserStatus
    FROM Users u
    LEFT JOIN PostStats ps ON u.Id = ps.OwnerUserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.AccountId
),
PostAnalysis AS (
    SELECT 
        ps.Id,
        ps.PostTypeId,
        ps.OwnerUserId,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.ActivityScore,
        ps.DaysSinceCreation,
        ps.UserPostRank,
        ps.ScoreRank,
        ps.ScorePercentile,
        ps.AvgScorePerUser,
        ps.TotalPostsPerUser,
        ps.IsQuestion,
        ps.IsAnswer,
        ps.HasComments,
        ps.HasAnswers,
        ps.IsBookmarked,
        ps.ScoreCategory,
        ps.PreviousScore,
        ps.NextScore,
        ps.ScoreDecile,
        ps.CleanTags,
        ps.TagsLength,
        ps.HasTags,
        ps.TrimmedTags,
        ROW_NUMBER() OVER (PARTITION BY ps.OwnerUserId ORDER BY ps.CreationDate) as UserPostSequence,
        CASE 
            WHEN ps.TotalPostsPerUser > 100 THEN 'High Volume'
            WHEN ps.TotalPostsPerUser > 10 THEN 'Medium Volume'
            ELSE 'Low Volume'
        END as PostVolumeCategory,
        CASE 
            WHEN ps.DaysSinceCreation > 30 THEN 1
            ELSE 0
        END as LongLivedPost,
        CASE 
            WHEN ps.Score > (SELECT AVG(Score) FROM PostStats) THEN 1
            ELSE 0
        END as AboveAverageScore,
        CASE 
            WHEN ps.Score = (SELECT MAX(Score) FROM PostStats) THEN 1
            ELSE 0
        END as HighestScoringPost,
        CASE 
            WHEN ps.Score < (SELECT MIN(Score) FROM PostStats) THEN 1
            ELSE 0
        END as LowestScoringPost,
        COALESCE(ps.PreviousScore, ps.Score) as EffectivePreviousScore,
        COALESCE(ps.NextScore, ps.Score) as EffectiveNextScore,
        ABS(ps.Score - COALESCE(ps.PreviousScore, ps.Score)) as ScoreChange,
        COALESCE(ps.TrimmedTags, '') as CleanTagList
    FROM PostStats ps
),
QuestionAnalysis AS (
    SELECT 
        pa.Id,
        pa.PostTypeId,
        pa.OwnerUserId,
        pa.Score,
        pa.ViewCount,
        pa.AnswerCount,
        pa.CommentCount,
        pa.FavoriteCount,
        pa.ActivityScore,
        pa.DaysSinceCreation,
        pa.UserPostRank,
        pa.ScoreRank,
        pa.ScorePercentile,
        pa.AvgScorePerUser,
        pa.TotalPostsPerUser,
        pa.IsQuestion,
        pa.IsAnswer,
        pa.HasComments,
        pa.HasAnswers,
        pa.IsBookmarked,
        pa.ScoreCategory,
        pa.PreviousScore,
        pa.NextScore,
        pa.ScoreDecile,
        pa.CleanTags,
        pa.TagsLength,
        pa.HasTags,
        pa.TrimmedTags,
        pa.UserPostSequence,
        pa.PostVolumeCategory,
        pa.LongLivedPost,
        pa.AboveAverageScore,
        pa.HighestScoringPost,
        pa.LowestScoringPost,
        pa.EffectivePreviousScore,
        pa.EffectiveNextScore,
        pa.ScoreChange,
        pa.CleanTagList,
        CASE 
            WHEN pa.AnswerCount > 0 AND pa.AnswerCount <= 5 THEN 1
            WHEN pa.AnswerCount > 5 THEN 2
            ELSE 0
        END as AnswerCountCategory,
        CASE 
            WHEN pa.CommentCount > 0 AND pa.CommentCount <= 10 THEN 1
            WHEN pa.CommentCount > 10 THEN 2
            ELSE 0
        END as CommentCountCategory,
        CASE 
            WHEN pa.ViewCount > 1000 THEN 1
            WHEN pa.ViewCount > 100 THEN 2
            ELSE 0
        END as ViewCountCategory,
        CASE 
            WHEN pa.FavoriteCount > 0 AND pa.FavoriteCount <= 5 THEN 1
            WHEN pa.FavoriteCount > 5 THEN 2
            ELSE 0
        END as FavoriteCountCategory,
        CASE 
            WHEN pa.ScoreChange > 50 THEN 1
            WHEN pa.ScoreChange > 10 THEN 2
            ELSE 0
        END as ScoreChangeCategory,
        (CASE 
            WHEN pa.HasTags = 1 THEN 1 
            ELSE 0 
        END + 
        CASE 
            WHEN pa.HasComments = 1 THEN 1 
            ELSE 0 
        END + 
        CASE 
            WHEN pa.HasAnswers = 1 THEN 1 
            ELSE 0 
        END + 
        CASE 
            WHEN pa.IsBookmarked = 1 THEN 1 
            ELSE 0 
        END) as EngagementLevel
    FROM PostAnalysis pa
    WHERE pa.IsQuestion = 1
)
SELECT 
    COUNT(*) as TotalQuestions,
    COUNT(DISTINCT qa.OwnerUserId) as DistinctQuestionOwners,
    AVG(qa.Score) as AvgQuestionsScore,
    SUM(qa.ViewCount) as TotalViews,
    SUM(qa.AnswerCount) as TotalAnswers,
    AVG(qa.AnswerCount) as AvgAnswersPerQuestion,
    AVG(qa.CommentCount) as AvgCommentsPerQuestion,
    AVG(qa.FavoriteCount) as AvgFavoritesPerQuestion,
    MAX(qa.Score) as MaxScore,
    MIN(qa.Score) as MinScore,
    ROUND(STDDEV(qa.Score), 2) as ScoreStandardDeviation,
    COUNT(*) OVER() as OverallTotalQuestions,
    COUNT(CASE WHEN qa.AnswerCount = 0 THEN 1 END) as QuestionsWithoutAnswers,
    COUNT(CASE WHEN qa.AnswerCount >= 1 THEN 1 END) as QuestionsWithAnswers,
    COUNT(CASE WHEN qa.HasComments = 1 THEN 1 END) as QuestionsWithComments,
    COUNT(CASE WHEN qa.IsBookmarked = 1 THEN 1 END) as QuestionsBookmarked,
    COUNT(CASE WHEN qa.LongLivedPost = 1 THEN 1 END) as LongLivedQuestions,
    COUNT(CASE WHEN qa.AboveAverageScore = 1 THEN 1 END) as AboveAverageQuestions,
    COUNT(CASE WHEN qa.HighestScoringPost = 1 THEN 1 END) as HighestScoringQuestions,
    COUNT(CASE WHEN qa.LowestScoringPost = 1 THEN 1 END) as LowestScoringQuestions,
    COUNT(CASE WHEN qa.PostVolumeCategory = 'High Volume' THEN 1 END) as HighVolumeQuestions,
    COUNT(CASE WHEN qa.PostVolumeCategory = 'Medium Volume' THEN 1 END) as MediumVolumeQuestions,
    COUNT(CASE WHEN qa.PostVolumeCategory = 'Low Volume' THEN 1 END) as LowVolumeQuestions,
    ROUND(AVG(qa.DaysSinceCreation), 2) as AvgDaysSinceCreation,
    STRING_AGG(DISTINCT CASE WHEN qa.HasTags = 1 THEN qa.TrimmedTags END, ', ') as AllTagCombinations,
    COUNT(DISTINCT CASE WHEN qa.HasTags = 1 THEN qa.TrimmedTags END) as UniqueTagCombinations,
    MIN(qa.DaysSinceCreation) as MinDaysSinceCreation,
    MAX(qa.DaysSinceCreation) as MaxDaysSinceCreation,
    AVG(qa.ScoreChange) as AvgScoreChange,
    MAX(qa.ScoreChange) as MaxScoreChange,
    MIN(qa.ScoreChange) as MinScoreChange,
    CASE 
        WHEN COUNT(*) > 0 THEN (
            SELECT COUNT(*) 
            FROM (SELECT qa.OwnerUserId, COUNT(*) as PostCount 
                  FROM QuestionAnalysis qa 
                  GROUP BY qa.OwnerUserId 
                  HAVING COUNT(*) > 100) sub_q
        )
        ELSE 0
    END as UsersWithMoreThan100Questions,
    CASE 
        WHEN COUNT(*) > 0 THEN (
            SELECT COUNT(*) 
            FROM (SELECT qa.OwnerUserId, COUNT(*) as PostCount 
                  FROM QuestionAnalysis qa 
                  GROUP BY qa.OwnerUserId 
                  HAVING COUNT(*) > 50) sub_q
        )
        ELSE 0
    END as UsersWithMoreThan50Questions,
    CASE 
        WHEN COUNT(*) > 0 THEN (
            SELECT COUNT(*) 
            FROM (SELECT qa.OwnerUserId, COUNT(*) as PostCount 
                  FROM QuestionAnalysis qa 
                  GROUP BY qa.OwnerUserId 
                  HAVING COUNT(*) BETWEEN 10 AND 50) sub_q
        )
        ELSE 0
    END as UsersWith10To50Questions,
    CASE 
        WHEN COUNT(*) > 0 THEN (
            SELECT COUNT(*) 
            FROM (SELECT qa.OwnerUserId, COUNT(*) as PostCount 
                  FROM QuestionAnalysis qa 
                  GROUP BY qa.OwnerUserId 
                  HAVING COUNT(*) < 10) sub_q
        )
        ELSE 0
    END as UsersWithLessThan10Questions,
    STRING_AGG(CAST(qa.ScoreCategory AS VARCHAR), ', ') as ScoreCategories,
    STRING_AGG(CAST(qa.AnswerCountCategory AS VARCHAR), ', ') as AnswerCountCategories,
    STRING_AGG(CAST(qa.CommentCountCategory AS VARCHAR), ', ') as CommentCountCategories,
    STRING_AGG(CAST(qa.ViewCountCategory AS VARCHAR), ', ') as ViewCountCategories,
    STRING_AGG(CAST(qa.FavoriteCountCategory AS VARCHAR), ', ') as FavoriteCountCategories,
    STRING_AGG(CAST(qa.ScoreChangeCategory AS VARCHAR), ', ') as ScoreChangeCategories,
    STRING_AGG(CAST(qa.EngagementLevel AS VARCHAR), ', ') as EngagementLevels,
    STRING_AGG(CAST(qa.UserPostSequence AS VARCHAR), ', ') as UserPostSequences,
    STRING_AGG(CAST(qa.ScoreDecile AS VARCHAR), ', ') as ScoreDeciles,
    STRING_AGG(CAST(qa.ScorePercentile AS VARCHAR), ', ') as ScorePercentiles,
    STRING_AGG(CAST(qa.AvgScorePerUser AS VARCHAR), ', ') as AvgScoresPerUser,
    STRING_AGG(CAST(qa.TotalPostsPerUser AS VARCHAR), ', ') as TotalPostsPerUser,
    STRING_AGG(CAST(qa.UserPostRank AS VARCHAR), ', ') as UserPostRanks,
    STRING_AGG(CAST(qa.ScoreRank AS VARCHAR), ', ') as ScoreRanks,
    STRING_AGG(CAST(qa.DaysSinceCreation AS VARCHAR), ', ') as DaysSinceCreations,
    STRING_AGG(CAST(qa.ActivityScore AS VARCHAR), ', ') as ActivityScores,
    STRING_AGG(CAST(qa.TagsLength AS VARCHAR), ', ') as TagsLengths,
    STRING_AGG(CAST(qa.HasTags AS VARCHAR), ', ') as HasTagsList,
    STRING_AGG(CAST(qa.HasComments AS VARCHAR), ', ') as HasCommentsList,
    STRING_AGG(CAST(qa.HasAnswers AS VARCHAR), ', ') as HasAnswersList,
    STRING_AGG(CAST(qa.IsBookmarked AS VARCHAR), ', ') as IsBookmarkedList,
    STRING_AGG(CAST(qa.IsQuestion AS VARCHAR), ', ') as IsQuestionsList,
    STRING_AGG(CAST(qa.IsAnswer AS VARCHAR), ', ') as IsAnswersList,
    STRING_AGG(CAST(qa.LongLivedPost AS VARCHAR), ', ') as LongLivedPostsList,
    STRING_AGG(CAST(qa.AboveAverageScore AS VARCHAR), ', ') as AboveAverageScoresList,
    STRING_AGG(CAST(qa.HighestScoringPost AS VARCHAR), ', ') as HighestScoringPostsList,
    STRING_AGG(CAST(qa.LowestScoringPost AS VARCHAR), ', ') as LowestScoringPostsList,
    STRING_AGG(CAST(qa.PostVolumeCategory AS VARCHAR), ', ') as PostVolumeCategoriesList,
    STRING_AGG(CAST(qa.PreviousScore AS VARCHAR), ', ') as PreviousScoresList,
    STRING_AGG(CAST(qa.NextScore AS VARCHAR), ', ') as NextScoresList,
    STRING_AGG(CAST(qa.EffectivePreviousScore AS VARCHAR), ', ') as EffectivePreviousScoresList,
    STRING_AGG(CAST(qa.EffectiveNextScore AS VARCHAR), ', ') as EffectiveNextScoresList
FROM QuestionAnalysis qa
WHERE qa.Id IS NOT NULL
AND qa.PostTypeId = 1
AND qa.OwnerUserId IS NOT NULL
AND qa.Score IS NOT NULL
AND qa.ViewCount IS NOT NULL
AND qa.AnswerCount IS NOT NULL
AND qa.CommentCount IS NOT NULL
AND qa.FavoriteCount IS NOT NULL;
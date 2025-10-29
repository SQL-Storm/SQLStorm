-- {"query": "7257.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2871} 
WITH PostStats AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.ParentId,
        p.AcceptedAnswerId,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as UserPostSequence,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) as ScoreRank,
        LAG(p.Score) OVER (ORDER BY p.CreationDate) as PrevScore,
        LEAD(p.Score) OVER (ORDER BY p.CreationDate) as NextScore,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) as TotalUserPosts,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as AvgUserScore,
        CASE 
            WHEN p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'AboveAvg'
            WHEN p.Score < (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'BelowAvg'
            ELSE 'Avg'
        END as ScoreCategory,
        COALESCE(p.Tags, '') as CleanTags,
        REPLACE(REPLACE(REPLACE(REPLACE(p.Title, '<', ''), '>', ''), '&', ''), '"', '') as CleanTitle,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN (p.AnswerCount * 100.0 / NULLIF(p.ViewCount, 0))
            ELSE NULL 
        END as AnswerViewRatio,
        DATEDIFF(day, p.CreationDate, COALESCE(p.LastEditDate, p.CreationDate)) as DaysSinceLastEdit
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserMetrics AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.AccountId,
        COUNT(DISTINCT ps.Id) as TotalPosts,
        AVG(ps.Score) as AvgPostScore,
        MAX(ps.CreationDate) as LastPostDate,
        STRING_AGG(DISTINCT ps.Title, '; ') as UserPostTitles,
        STRING_AGG(DISTINCT ps.Tags, '; ') as UserPostTags,
        CASE 
            WHEN COUNT(DISTINCT ps.Id) > 0 AND AVG(ps.Score) > 10 THEN 'HighlyActive'
            WHEN COUNT(DISTINCT ps.Id) > 0 AND AVG(ps.Score) > 0 THEN 'Active'
            ELSE 'Inactive'
        END as ActivityLevel,
        COUNT(DISTINCT CASE WHEN ps.PostTypeId = 1 THEN ps.Id END) as QuestionCount
    FROM Users u
    LEFT JOIN PostStats ps ON u.Id = ps.OwnerUserId
    GROUP BY u.Id, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.AccountId
),
TopQuestions AS (
    SELECT 
        ps.Id,
        ps.Title,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.OwnerUserId,
        ps.CreationDate,
        ps.Tags,
        ps.ScoreRank,
        ps.ScoreCategory,
        ps.AnswerViewRatio,
        ps.DaysSinceLastEdit,
        ps.UserPostSequence,
        ps.TotalUserPosts,
        ps.AvgUserScore,
        ps.PrevScore,
        ps.NextScore,
        ROW_NUMBER() OVER (ORDER BY ps.Score DESC, ps.ViewCount DESC) as RankByScoreAndViews,
        RANK() OVER (PARTITION BY ps.OwnerUserId ORDER BY ps.ViewCount DESC) as UserViewRank,
        DENSE_RANK() OVER (ORDER BY ps.ViewCount DESC) as ViewRank,
        CASE 
            WHEN ps.AnswerCount = 0 AND ps.Score > 0 THEN 'Unanswered'
            WHEN ps.AnswerCount > 0 AND ps.AcceptedAnswerId IS NOT NULL THEN 'Answered-Accepted'
            WHEN ps.AnswerCount > 0 THEN 'Answered-NotAccepted'
            ELSE 'NoAnswers'
        END as AnswerStatus
    FROM PostStats ps
    WHERE ps.PostTypeId = 1 AND ps.Score > 0
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > (SELECT AVG(Count) FROM Tags) THEN 'Popular'
            WHEN t.Count < (SELECT AVG(Count) FROM Tags) THEN 'LessPopular'
            ELSE 'Average'
        END as PopularityLevel,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as TagRank,
        DENSE_RANK() OVER (ORDER BY t.Count DESC) as TagDensityRank,
        NTILE(4) OVER (ORDER BY t.Count DESC) as TagQuartile
    FROM Tags t
),
AnswerAnalysis AS (
    SELECT 
        ps.Id as AnswerId,
        ps.ParentId,
        ps.Score,
        ps.CreationDate,
        ps.OwnerUserId,
        ps.LastEditDate,
        ps.AnswerCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.PrevScore,
        ps.NextScore,
        ps.ScoreRank,
        ps.ScoreCategory,
        ROW_NUMBER() OVER (PARTITION BY ps.ParentId ORDER BY ps.Score DESC, ps.CreationDate ASC) as AnswerRank,
        RANK() OVER (PARTITION BY ps.OwnerUserId ORDER BY ps.Score DESC) as UserAnswerRank,
        CASE 
            WHEN ps.Score = (SELECT MAX(Score) FROM Posts WHERE ParentId = ps.ParentId AND PostTypeId = 2) 
            THEN 1 ELSE 0 END as IsBestAnswer
    FROM PostStats ps 
    WHERE ps.PostTypeId = 2
)
SELECT 
    'PerformanceBenchmark' as QueryType,
    COUNT(*) as TotalRecords,
    COUNT(DISTINCT tq.Id) as UniqueQuestions,
    COUNT(DISTINCT u.Id) as UniqueUsers,
    COUNT(DISTINCT ta.TagName) as TotalTags,
    COUNT(DISTINCT CASE WHEN tq.AnswerStatus = 'Answered-Accepted' THEN tq.Id END) as AcceptedAnswers,
    COUNT(DISTINCT CASE WHEN tq.AnswerStatus = 'Unanswered' THEN tq.Id END) as UnansweredQuestions,
    AVG(tq.Score) as AvgQuestionScore,
    AVG(tq.ViewCount) as AvgQuestionViews,
    AVG(CASE WHEN tq.AnswerViewRatio IS NOT NULL THEN tq.AnswerViewRatio END) as AvgAnswerViewRatio,
    SUM(tq.AnswerCount) as TotalAnswers,
    SUM(tq.CommentCount) as TotalComments,
    MAX(tq.CreationDate) as LatestQuestion,
    MIN(tq.CreationDate) as EarliestQuestion,
    STRING_AGG(DISTINCT CASE WHEN tq.AnswerStatus = 'Answered-NotAccepted' THEN tq.Title END, '; ') as NonAcceptedAnswers,
    STRING_AGG(DISTINCT CASE WHEN tq.AnswerStatus = 'Unanswered' THEN tq.Title END, '; ') as UnansweredQuestionsList,
    STRING_AGG(DISTINCT u.DisplayName, '; ') as UserList,
    STRING_AGG(DISTINCT ta.TagName, '; ') as PopularTags,
    STRING_AGG(DISTINCT CASE WHEN tq.ScoreRank <= 10 THEN tq.Title END, '; ') as Top10ScoreQuestions,
    COUNT(DISTINCT CASE WHEN tq.ScoreCategory = 'AboveAvg' AND tq.PostTypeId = 1 THEN tq.Id END) as AboveAvgQuestions,
    COUNT(DISTINCT CASE WHEN ta.PopularityLevel = 'Popular' THEN ta.TagName END) as PopularTagsCount,
    COUNT(DISTINCT CASE WHEN a.IsBestAnswer = 1 THEN a.AnswerId END) as TopAnswers,
    COUNT(DISTINCT CASE WHEN u.LastPostDate >= DATEADD(day, -30, GETDATE()) THEN u.Id END) as RecentActiveUsers,
    AVG(u.Reputation) as AvgUserReputation,
    SUM(u.UpVotes) as TotalUpVotes,
    SUM(u.DownVotes) as TotalDownVotes,
    AVG(CASE WHEN u.QuestionCount > 0 THEN u.QuestionCount END) as AvgQuestionsPerUser,
    MIN(tq.ViewRank) as LowestViewRank,
    MAX(tq.ScoreRank) as HighestScoreRank,
    COUNT(DISTINCT CASE WHEN tq.AnswerCount > 10 THEN tq.Id END) as HighAnswerCountQuestions,
    COUNT(DISTINCT CASE WHEN tq.DaysSinceLastEdit > 30 THEN tq.Id END) as OldQuestions,
    COUNT(DISTINCT CASE WHEN u.TotalPosts > 100 THEN u.UserId END) as HighPostUsers,
    STRING_AGG(DISTINCT CASE WHEN ta.TagQuartile <= 2 THEN ta.TagName END, '; ') as HighDensityTags,
    COUNT(DISTINCT CASE WHEN tq.UserPostSequence = 1 THEN tq.Id END) as FirstPosts,
    COUNT(DISTINCT CASE WHEN u.ActivityLevel = 'HighlyActive' THEN u.UserId END) as HighlyActiveUsers,
    COUNT(DISTINCT CASE WHEN a.AnswerRank = 1 THEN a.AnswerId END) as FirstRankedAnswers,
    COUNT(DISTINCT CASE WHEN tq.UserViewRank = 1 THEN tq.Id END) as TopViewedQuestions,
    COUNT(DISTINCT CASE WHEN tq.RankByScoreAndViews <= 5 THEN tq.Id END) as TopScoreAndViewQuestions,
    AVG(tq.AnswerCount) as AvgAnswersPerQuestion,
    MAX(tq.AnswerCount) as MaxAnswersPerQuestion,
    MIN(tq.AnswerCount) as MinAnswersPerQuestion,
    AVG(tq.CommentCount) as AvgCommentsPerQuestion,
    SUM(CASE WHEN tq.AnswerStatus = 'Answered-NotAccepted' THEN 1 ELSE 0 END) as NonAcceptedAnswersCount,
    COUNT(DISTINCT CASE WHEN tq.CreationDate >= DATEADD(year, -1, GETDATE()) THEN tq.Id END) as RecentQuestions,
    STRING_AGG(DISTINCT CASE WHEN tq.DaysSinceLastEdit > 90 THEN tq.Title END, '; ') as VeryOldQuestions,
    COUNT(DISTINCT CASE WHEN tq.Score > 100 THEN tq.Id END) as HighlyScoredQuestions,
    COUNT(DISTINCT CASE WHEN tq.ViewCount > 1000 THEN tq.Id END) as HighlyViewedQuestions,
    AVG(CASE WHEN tq.AnswerViewRatio IS NOT NULL THEN tq.AnswerViewRatio END) as AvgAnswerViewRatioFiltered,
    COUNT(DISTINCT CASE WHEN tq.IsBestAnswer = 1 THEN tq.Id END) as BestAnswerQuestions,
    SUM(CASE WHEN u.TotalPosts > 0 THEN u.TotalPosts END) as TotalUserPostsAggregate,
    COUNT(DISTINCT CASE WHEN u.Views > 1000 THEN u.UserId END) as HighViewUsers,
    STRING_AGG(DISTINCT CASE WHEN tq.Score > 50 AND tq.AnswerCount > 0 THEN tq.Title END, '; ') as HighScoreAnsweredQuestions,
    COUNT(DISTINCT CASE WHEN tq.Tags IS NOT NULL AND LTRIM(RTRIM(tq.Tags)) <> '' THEN tq.Id END) as TaggedQuestions,
    COUNT(DISTINCT CASE WHEN tq.LastEditDate IS NOT NULL AND tq.LastEditDate > tq.CreationDate THEN tq.Id END) as EditedQuestions,
    COUNT(DISTINCT CASE WHEN tq.AcceptedAnswerId IS NOT NULL THEN tq.Id END) as QuestionsWithAcceptedAnswers,
    COUNT(DISTINCT CASE WHEN tq.AnswerCount > 0 THEN tq.Id END) as AnsweredQuestions,
    COUNT(DISTINCT CASE WHEN tq.AnswerCount > 1 THEN tq.Id END) as MultipleAnsweredQuestions,
    COUNT(DISTINCT CASE WHEN tq.QuestionCount > 10 THEN u.UserId END) as MultipleQuestionUsers,
    AVG(CASE WHEN u.TotalPosts > 0 THEN u.TotalPosts END) as AvgUserPostCount,
    COUNT(DISTINCT CASE WHEN tq.Score > 10 AND tq.CommentCount > 5 THEN tq.Id END) as HighScoreHighCommentQuestions,
    STRING_AGG(DISTINCT CASE WHEN u.ActivityLevel = 'Active' THEN u.DisplayName END, '; ') as ActiveUsersList,
    COUNT(DISTINCT CASE WHEN tq.ScoreRank <= 50 THEN tq.Id END) as Top50ScoreQuestions,
    COUNT(DISTINCT CASE WHEN u.Reputation > 10000 THEN u.UserId END) as HighReputationUsers,
    COUNT(DISTINCT CASE WHEN ta.TagDensityRank <= 25 THEN ta.TagName END) as TopTagsDensity,
    COUNT(DISTINCT CASE WHEN tq.DaysSinceLastEdit < 7 THEN tq.Id END) as RecentQuestions,
    STRING_AGG(DISTINCT CASE WHEN a.UserAnswerRank = 1 THEN a.AnswerId END, '; ') as UserTopAnswers
FROM TopQuestions tq
FULL OUTER JOIN UserMetrics u ON u.UserId = tq.OwnerUserId
FULL OUTER JOIN TagAnalysis ta ON ta.TagRank <= 100
LEFT JOIN AnswerAnalysis a ON a.AnswerId = tq.Id
WHERE 
    (tq.Id IS NOT NULL OR u.UserId IS NOT NULL OR ta.TagName IS NOT NULL)
    AND (u.Reputation IS NOT NULL OR u.Views IS NOT NULL OR a.AnswerId IS NOT NULL)
    AND (ta.Count IS NOT NULL OR tq.PostTypeId = 1 OR a.AnswerRank IS NOT NULL)
ORDER BY tq.Score DESC, tq.ViewCount DESC
OFFSET 0 ROWS
FETCH NEXT 100000 ROWS ONLY;
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(p.Id) as TotalPosts,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        COUNT(DISTINCT c.Id) as Comments,
        COUNT(DISTINCT b.Id) as Badges,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        CASE 
            WHEN COUNT(p.Id) > 0 THEN 
                (COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) * 100.0 / COUNT(p.Id))
            ELSE 0 
        END as QuestionPercentage,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, COUNT(p.Id) DESC) as ReputationRank,
        NTILE(100) OVER (ORDER BY u.Reputation) as ReputationPercentile
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
PostWithComplexity AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Body,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.Tags,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END as PostType,
        COALESCE(
            NULLIF(LENGTH(p.Title), 0), 
            NULLIF(LENGTH(p.Body), 0), 
            0
        ) as ContentLength,
        CASE 
            WHEN p.Tags IS NOT NULL AND LENGTH(p.Tags) > 0 THEN 
                -- Convert tags like '<tag1><tag2>' into array by removing leading/trailing <> and splitting on '><'
                (CARDINALITY(STRING_TO_ARRAY(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><')) 
                 /* For dialects without CARDINALITY you can replace CARDINALITY(...) with ARRAY_LENGTH(...) or simply use array_length(...) as appropriate */)
            ELSE 0
        END as TagCount,
        CASE 
            WHEN p.Score > 10 THEN 'Highly Voted'
            WHEN p.Score > 0 THEN 'Moderately Voted'
            WHEN p.Score < 0 THEN 'Downvoted'
            ELSE 'No Votes'
        END as VoteCategory,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PrevScore,
        LEAD(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as NextScore,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as AvgUserScore,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as UserPostSequence,
        CASE 
            WHEN p.PostTypeId = 1 AND COALESCE(p.AnswerCount,0) > 0 THEN 1
            ELSE 0
        END as HasAnswers,
        CASE 
            WHEN COALESCE(p.CommentCount,0) > 5 THEN 1
            ELSE 0
        END as HasManyComments,
        CASE 
            WHEN COALESCE(p.ViewCount,0) > 1000 THEN 'High Traffic'
            WHEN COALESCE(p.ViewCount,0) > 100 THEN 'Medium Traffic'
            ELSE 'Low Traffic'
        END as TrafficLevel
    FROM Posts p
    WHERE p.Id IS NOT NULL
),
ComplexPostAnalysis AS (
    SELECT 
        pa.PostId,
        pa.Title,
        pa.OwnerUserId,
        pa.Score,
        pa.ViewCount,
        pa.AnswerCount,
        pa.CommentCount,
        pa.PostType,
        pa.ContentLength,
        pa.TagCount,
        pa.VoteCategory,
        pa.PrevScore,
        pa.NextScore,
        pa.AvgUserScore,
        pa.UserPostSequence,
        pa.HasAnswers,
        pa.HasManyComments,
        pa.TrafficLevel,
        CASE 
            WHEN pa.PostType = 'Question' AND pa.Score < 0 THEN 1
            WHEN pa.PostType = 'Answer' AND pa.Score < 0 THEN 1
            ELSE 0
        END as NegativeScoring,
        CASE 
            WHEN pa.HasManyComments = 1 AND pa.Score > 10 THEN 1
            ELSE 0
        END as PopularCommentedHighScore,
        CASE 
            WHEN pa.PostType = 'Question' AND COALESCE(pa.AnswerCount,0) > 10 THEN 1
            ELSE 0
        END as HighAnswerCount,
        CASE 
            WHEN pa.Score > 50 AND COALESCE(pa.ViewCount,0) > 500 THEN 1
            ELSE 0
        END as ViralContent
    FROM PostWithComplexity pa
),
PostHistorySummary AS (
    SELECT 
        ph.PostId,
        COUNT(*) as HistoryCount,
        COUNT(DISTINCT ph.PostHistoryTypeId) as DistinctTypes,
        MAX(ph.CreationDate) as LastEdit,
        STRING_AGG(ph.Comment, ', ') as AllComments,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10,11,12,13) THEN ph.UserId END) as EditorCount,
        STRING_AGG(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END, ', ') as CloseReasons,
        COUNT(DISTINCT CASE WHEN ph.UserId IS NOT NULL THEN ph.UserId END) as UniqueEditors
    FROM PostHistory ph
    WHERE ph.PostId IS NOT NULL AND ph.PostId > 0
    GROUP BY ph.PostId
),
TagAnalysis AS (
    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Very Popular'
            WHEN t.Count > 100 THEN 'Popular'
            WHEN t.Count > 10 THEN 'Moderate'
            ELSE 'Rare'
        END as PopularityLevel
    FROM Tags t
    WHERE t.TagName IS NOT NULL AND LENGTH(t.TagName) > 0
),
UserComplexityScores AS (
    SELECT 
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.TotalPosts,
        uas.Questions,
        uas.Answers,
        uas.Comments,
        uas.Badges,
        uas.ReputationRank,
        uas.ReputationPercentile,
        uas.QuestionPercentage,
        CASE 
            WHEN uas.Reputation > 100000 THEN 10
            WHEN uas.Reputation > 50000 THEN 9
            WHEN uas.Reputation > 10000 THEN 8
            WHEN uas.Reputation > 5000 THEN 7
            WHEN uas.Reputation > 1000 THEN 6
            WHEN uas.Reputation > 500 THEN 5
            WHEN uas.Reputation > 100 THEN 4
            WHEN uas.Reputation > 50 THEN 3
            WHEN uas.Reputation > 10 THEN 2
            ELSE 1
        END as ReputationLevel,
        CASE 
            WHEN uas.Questions > 100 THEN 10
            WHEN uas.Questions > 50 THEN 9
            WHEN uas.Questions > 25 THEN 8
            WHEN uas.Questions > 10 THEN 7
            WHEN uas.Questions > 5 THEN 6
            WHEN uas.Questions > 2 THEN 5
            WHEN uas.Questions > 1 THEN 4
            ELSE 3
        END as QuestionLevel,
        CASE 
            WHEN uas.Answers > 1000 THEN 10
            WHEN uas.Answers > 500 THEN 9
            WHEN uas.Answers > 250 THEN 8
            WHEN uas.Answers > 100 THEN 7
            WHEN uas.Answers > 50 THEN 6
            WHEN uas.Answers > 25 THEN 5
            WHEN uas.Answers > 10 THEN 4
            ELSE 3
        END as AnswerLevel,
        CASE 
            WHEN uas.Comments > 1000 THEN 10
            WHEN uas.Comments > 500 THEN 9
            WHEN uas.Comments > 250 THEN 8
            WHEN uas.Comments > 100 THEN 7
            WHEN uas.Comments > 50 THEN 6
            WHEN uas.Comments > 25 THEN 5
            WHEN uas.Comments > 10 THEN 4
            ELSE 3
        END as CommentLevel,
        CASE 
            WHEN uas.Badges > 50 THEN 10
            WHEN uas.Badges > 25 THEN 9
            WHEN uas.Badges > 10 THEN 8
            WHEN uas.Badges > 5 THEN 7
            WHEN uas.Badges > 2 THEN 6
            ELSE 5
        END as BadgeLevel,
        uas.ReputationRank + uas.QuestionPercentage + uas.ReputationPercentile as ComplexityScore,
        (CASE 
            WHEN uas.Reputation > 100000 THEN 10
            WHEN uas.Reputation > 50000 THEN 9
            WHEN uas.Reputation > 10000 THEN 8
            WHEN uas.Reputation > 5000 THEN 7
            WHEN uas.Reputation > 1000 THEN 6
            WHEN uas.Reputation > 500 THEN 5
            WHEN uas.Reputation > 100 THEN 4
            WHEN uas.Reputation > 50 THEN 3
            WHEN uas.Reputation > 10 THEN 2
            ELSE 1
        END
        + 
        CASE 
            WHEN uas.Questions > 100 THEN 10
            WHEN uas.Questions > 50 THEN 9
            WHEN uas.Questions > 25 THEN 8
            WHEN uas.Questions > 10 THEN 7
            WHEN uas.Questions > 5 THEN 6
            WHEN uas.Questions > 2 THEN 5
            WHEN uas.Questions > 1 THEN 4
            ELSE 3
        END
        + 
        CASE 
            WHEN uas.Answers > 1000 THEN 10
            WHEN uas.Answers > 500 THEN 9
            WHEN uas.Answers > 250 THEN 8
            WHEN uas.Answers > 100 THEN 7
            WHEN uas.Answers > 50 THEN 6
            WHEN uas.Answers > 25 THEN 5
            WHEN uas.Answers > 10 THEN 4
            ELSE 3
        END
        + 
        CASE 
            WHEN uas.Comments > 1000 THEN 10
            WHEN uas.Comments > 500 THEN 9
            WHEN uas.Comments > 250 THEN 8
            WHEN uas.Comments > 100 THEN 7
            WHEN uas.Comments > 50 THEN 6
            WHEN uas.Comments > 25 THEN 5
            WHEN uas.Comments > 10 THEN 4
            ELSE 3
        END
        + 
        CASE 
            WHEN uas.Badges > 50 THEN 10
            WHEN uas.Badges > 25 THEN 9
            WHEN uas.Badges > 10 THEN 8
            WHEN uas.Badges > 5 THEN 7
            WHEN uas.Badges > 2 THEN 6
            ELSE 5
        END
        ) * (CASE WHEN uas.Comments > 10 THEN 1.5 ELSE 1.0 END) as WeightedComplexityScore
    FROM UserActivityStats uas
),
FinalPostAnalysis AS (
    SELECT 
        cpa.PostId,
        cpa.Title,
        cpa.OwnerUserId,
        cpa.Score,
        cpa.ViewCount,
        cpa.AnswerCount,
        cpa.CommentCount,
        cpa.PostType,
        cpa.ContentLength,
        cpa.TagCount,
        cpa.VoteCategory,
        cpa.PrevScore,
        cpa.NextScore,
        cpa.AvgUserScore,
        cpa.UserPostSequence,
        cpa.HasAnswers,
        cpa.HasManyComments,
        cpa.TrafficLevel,
        cpa.NegativeScoring,
        cpa.PopularCommentedHighScore,
        cpa.HighAnswerCount,
        cpa.ViralContent,
        phs.HistoryCount,
        phs.DistinctTypes,
        phs.LastEdit,
        phs.EditorCount,
        phs.CloseReasons,
        phs.UniqueEditors,
        CASE 
            WHEN phs.HistoryCount > 10 THEN 10
            WHEN phs.HistoryCount > 5 THEN 8
            WHEN phs.HistoryCount > 3 THEN 6
            WHEN phs.HistoryCount > 1 THEN 4
            ELSE 2
        END as EditActivityLevel,
        CASE 
            WHEN phs.DistinctTypes > 5 THEN 10
            WHEN phs.DistinctTypes > 3 THEN 8
            WHEN phs.DistinctTypes > 1 THEN 6
            ELSE 4
        END as EditDiversityLevel,
        CASE 
            WHEN cpa.Score > 100 THEN 10
            WHEN cpa.Score > 50 THEN 8
            WHEN cpa.Score > 25 THEN 6
            WHEN cpa.Score > 10 THEN 4
            WHEN cpa.Score > 0 THEN 2
            ELSE 1
        END as ScoreLevel,
        CASE 
            WHEN cpa.AnswerCount > 50 THEN 10
            WHEN cpa.AnswerCount > 20 THEN 8
            WHEN cpa.AnswerCount > 10 THEN 6
            WHEN cpa.AnswerCount > 5 THEN 4
            WHEN cpa.AnswerCount > 0 THEN 2
            ELSE 1
        END as AnswerLevel,
        CASE 
            WHEN cpa.ViewCount > 10000 THEN 10
            WHEN cpa.ViewCount > 5000 THEN 8
            WHEN cpa.ViewCount > 1000 THEN 6
            WHEN cpa.ViewCount > 500 THEN 4
            WHEN cpa.ViewCount > 100 THEN 2
            ELSE 1
        END as ViewLevel
    FROM ComplexPostAnalysis cpa
    LEFT JOIN PostHistorySummary phs ON cpa.PostId = phs.PostId
),
UserPostMetrics AS (
    SELECT 
        ucs.UserId,
        ucs.DisplayName,
        ucs.Reputation,
        ucs.TotalPosts,
        ucs.Questions,
        ucs.Answers,
        ucs.Comments,
        ucs.Badges,
        ucs.ReputationRank,
        ucs.ReputationPercentile,
        ucs.QuestionPercentage,
        ucs.ReputationLevel,
        ucs.QuestionLevel,
        ucs.AnswerLevel,
        ucs.CommentLevel,
        ucs.BadgeLevel,
        ucs.ComplexityScore,
        ucs.WeightedComplexityScore,
        COALESCE(
            AVG(fpa.Score) OVER (PARTITION BY ucs.UserId), 
            0
        ) as AvgPostScore,
        COALESCE(
            AVG(fpa.ViewCount) OVER (PARTITION BY ucs.UserId), 
            0
        ) as AvgPostViews,
        COALESCE(
            AVG(fpa.AnswerCount) OVER (PARTITION BY ucs.UserId), 
            0
        ) as AvgAnswers,
        COALESCE(
            AVG(fpa.CommentCount) OVER (PARTITION BY ucs.UserId), 
            0
        ) as AvgComments,
        COUNT(*) OVER (PARTITION BY ucs.UserId) as PostCount,
        COUNT(CASE WHEN fpa.HasAnswers = 1 THEN 1 END) OVER (PARTITION BY ucs.UserId) as AnsweredPosts,
        COUNT(CASE WHEN fpa.HasManyComments = 1 THEN 1 END) OVER (PARTITION BY ucs.UserId) as CommentedPosts,
        COALESCE(
            COUNT(fpa.PostId) OVER (PARTITION BY ucs.UserId)
        , 0) as UniquePosts,
        COALESCE(
            AVG(
                CASE WHEN fpa.Score >= 0 THEN 1 ELSE 0 END
            ) OVER (PARTITION BY ucs.UserId)
        , 0) as PositiveRatingRatio
    FROM UserComplexityScores ucs
    LEFT JOIN FinalPostAnalysis fpa ON ucs.UserId = fpa.OwnerUserId
)
SELECT 
    upm.UserId,
    upm.DisplayName,
    upm.Reputation,
    upm.TotalPosts,
    upm.Questions,
    upm.Answers,
    upm.Comments,
    upm.Badges,
    upm.ReputationRank,
    upm.ReputationPercentile,
    upm.QuestionPercentage,
    upm.ReputationLevel,
    upm.QuestionLevel,
    upm.AnswerLevel,
    upm.CommentLevel,
    upm.BadgeLevel,
    upm.ComplexityScore,
    upm.WeightedComplexityScore,
    upm.AvgPostScore,
    upm.AvgPostViews,
    upm.AvgAnswers,
    upm.AvgComments,
    upm.PostCount,
    upm.AnsweredPosts,
    upm.CommentedPosts,
    upm.UniquePosts,
    upm.PositiveRatingRatio,
    COALESCE(
        STRING_AGG(
            (CASE WHEN upm.QuestionLevel >= 8 THEN 'Highly Active Questioner' ELSE '' END) ||
            (CASE WHEN upm.AnswerLevel >= 8 THEN 'Highly Active Answerer' ELSE '' END) ||
            (CASE WHEN upm.CommentLevel >= 8 THEN 'Highly Active Commenter' ELSE '' END) ||
            (CASE WHEN upm.ReputationLevel >= 8 THEN 'Highly Ranked User' ELSE '' END) ||
            (CASE WHEN upm.BadgeLevel >= 8 THEN 'Highly Recognized User' ELSE '' END)
            , ', '
        ), ''
    ) as UserActivityProfiles,
    CASE 
        WHEN upm.Reputation > 10000 AND upm.TotalPosts > 100 THEN 'Power User'
        WHEN upm.Reputation > 1000 AND upm.TotalPosts > 50 THEN 'Active User'
        WHEN upm.Reputation > 100 AND upm.TotalPosts > 10 THEN 'Regular User'
        WHEN upm.Reputation > 50 THEN 'New User'
        ELSE 'Casual User'
    END as UserCategory,
    ROW_NUMBER() OVER (ORDER BY upm.ComplexityScore DESC, upm.WeightedComplexityScore DESC) as PerformanceRank,
    PERCENT_RANK() OVER (ORDER BY upm.WeightedComplexityScore DESC) as PerformancePercentile,
    NTILE(10) OVER (ORDER BY upm.WeightedComplexityScore DESC) as PerformanceDecile,
    CASE 
        WHEN upm.QuestionLevel > 8 AND upm.AnswerLevel > 8 THEN 'Full Stack Contributor'
        WHEN upm.QuestionLevel > 8 THEN 'Question Expert'
        WHEN upm.AnswerLevel > 8 THEN 'Answer Expert'
        WHEN upm.QuestionLevel > 5 OR upm.AnswerLevel > 5 THEN 'Active Contributor'
        ELSE 'Contributor'
    END as ContributionLevel,
    CASE 
        WHEN upm.Reputation > 50000 AND upm.Badges > 20 THEN ('Master ' || upm.DisplayName)
        WHEN upm.Reputation > 10000 AND upm.Badges > 10 THEN ('Expert ' || upm.DisplayName)
        WHEN upm.Reputation > 1000 AND upm.Badges > 5 THEN ('Intermediate ' || upm.DisplayName)
        WHEN upm.Reputation > 100 THEN ('Beginner ' || upm.DisplayName)
        ELSE ('Novice ' || upm.DisplayName)
    END as UserIdentifier,
    CAST((upm.AvgPostScore * upm.AvgPostViews * upm.PositiveRatingRatio) AS NUMERIC(15,2)) as ActivityScore,
    CASE 
        WHEN (upm.AvgPostViews + upm.AvgAnswers + upm.AvgComments) > 1000 THEN 'Extreme Engagement'
        WHEN (upm.AvgPostViews + upm.AvgAnswers + upm.AvgComments) > 500 THEN 'High Engagement'
        WHEN (upm.AvgPostViews + upm.AvgAnswers + upm.AvgComments) > 100 THEN 'Medium Engagement'
        WHEN (upm.AvgPostViews + upm.AvgAnswers + upm.AvgComments) > 50 THEN 'Low Engagement'
        ELSE 'Minimal Engagement'
    END as EngagementLevel
FROM UserPostMetrics upm
WHERE upm.UserId IS NOT NULL AND upm.TotalPosts > 0
GROUP BY 
    upm.UserId, upm.DisplayName, upm.Reputation, upm.TotalPosts, upm.Questions, 
    upm.Answers, upm.Comments, upm.Badges, upm.ReputationRank, upm.ReputationPercentile,
    upm.QuestionPercentage, upm.ReputationLevel, upm.QuestionLevel, upm.AnswerLevel,
    upm.CommentLevel, upm.BadgeLevel, upm.ComplexityScore, upm.WeightedComplexityScore,
    upm.AvgPostScore, upm.AvgPostViews, upm.AvgAnswers, upm.AvgComments, upm.PostCount,
    upm.AnsweredPosts, upm.CommentedPosts, upm.UniquePosts, upm.PositiveRatingRatio
HAVING 
    COUNT(*) > 0 
    AND SUM(CASE WHEN upm.QuestionLevel >= 7 OR upm.AnswerLevel >= 7 THEN 1 ELSE 0 END) > 0
ORDER BY 
    upm.WeightedComplexityScore DESC,
    upm.ComplexityScore DESC,
    upm.Reputation DESC,
    upm.TotalPosts DESC,
    upm.AvgPostScore DESC
LIMIT 1000;
-- {"query": "7694.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 7229} 
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
        RANK() OVER (ORDER BY u.Reputation DESC) as ReputationRank,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as PostActivityRank,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        COALESCE(SUM(p.ViewCount), 0) as TotalViews,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 0 THEN 
                COALESCE(SUM(p.Score), 0) * 1.0 / COUNT(DISTINCT p.Id)
            ELSE 0 
        END as AvgScorePerPost,
        CASE 
            WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0 THEN 
                COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) * 1.0 / 
                COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END)
            ELSE 0 
        END as AvgScorePerQuestion,
        CASE 
            WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) > 0 THEN 
                COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) * 1.0 / 
                COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END)
            ELSE 0 
        END as AvgScorePerAnswer,
        COALESCE(SUM(CASE WHEN p.CreationDate >= '2023-01-01' THEN 1 ELSE 0 END), 0) as RecentPosts,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 AND p.CreationDate >= '2023-01-01' THEN 1 ELSE 0 END), 0) as RecentQuestions,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 AND p.CreationDate >= '2023-01-01' THEN 1 ELSE 0 END), 0) as RecentAnswers
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId OR u.Id = p.LastEditorUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TopUsers AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (ORDER BY TotalScore DESC) as ScoreRank,
        ROW_NUMBER() OVER (ORDER BY TotalViews DESC) as ViewRank,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC) as RepRank
    FROM UserActivityStats
    WHERE TotalPosts > 0
),
PostTagAnalytics AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Body,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Tags,
        COALESCE(p.AnswerCount, 0) as AnswerCount,
        COALESCE(p.CommentCount, 0) as CommentCount,
        COALESCE(p.FavoriteCount, 0) as FavoriteCount,
        COALESCE(p.AcceptedAnswerId, 0) as AcceptedAnswerId,
        CASE WHEN p.PostTypeId = 1 THEN 'Question' ELSE 'Answer' END as PostType,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END as IsClosed,
        CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END as IsCommunityOwned,
        CASE 
            WHEN p.Tags IS NOT NULL AND LENGTH(p.Tags) > 0 THEN 
                ARRAY_LENGTH(string_to_array(trim(trim(p.Tags, '<>'), '><'), '><'), 1)
            ELSE 0 
        END as TagCount,
        CASE 
            WHEN p.Tags IS NOT NULL AND LENGTH(p.Tags) > 0 THEN 
                array_to_string(string_to_array(trim(trim(p.Tags, '<>'), '><'), '><'), ', ')
            ELSE '' 
        END as TagsList,
        SUBSTRING(p.Body, 1, 200) as BodyPreview,
        TRIM(p.Title) as TrimmedTitle,
        LENGTH(p.Title) as TitleLength,
        LENGTH(p.Body) as BodyLength,
        EXTRACT(YEAR FROM p.CreationDate) as PostYear,
        EXTRACT(MONTH FROM p.CreationDate) as PostMonth,
        EXTRACT(DAY FROM p.CreationDate) as PostDay
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) 
),
TagUsageStats AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        COUNT(DISTINCT p.Id) as QuestionCount,
        AVG(COALESCE(p.Score, 0)) as AvgScore,
        AVG(COALESCE(p.ViewCount, 0)) as AvgViews,
        MAX(p.CreationDate) as LastUsed,
        AVG(COALESCE(p.CommentCount, 0)) as AvgComments,
        AVG(COALESCE(p.AnswerCount, 0)) as AvgAnswers,
        COALESCE(SUM(COALESCE(p.Score, 0)), 0) as TotalScore,
        COALESCE(SUM(COALESCE(p.ViewCount, 0)), 0) as TotalViews,
        STRING_AGG(DISTINCT p.Title, ' | ' ORDER BY p.CreationDate DESC LIMIT 5) as RecentQuestions,
        STRING_AGG(DISTINCT p.OwnerUserId::TEXT, ', ' ORDER BY p.CreationDate DESC LIMIT 10) as ActiveUsers
    FROM Tags t
    LEFT JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
    GROUP BY t.TagName, t.Count
),
CombinedMetrics AS (
    SELECT 
        tu.UserId,
        tu.DisplayName,
        tu.Reputation,
        tu.Views,
        tu.UpVotes,
        tu.DownVotes,
        tu.TotalPosts,
        tu.Questions,
        tu.Answers,
        tu.Comments,
        tu.Badges,
        tu.LastPostDate,
        tu.LastCommentDate,
        tu.ReputationRank,
        tu.PostActivityRank,
        tu.TotalScore,
        tu.TotalViews,
        tu.AvgScorePerPost,
        tu.AvgScorePerQuestion,
        tu.AvgScorePerAnswer,
        tu.RecentPosts,
        tu.RecentQuestions,
        tu.RecentAnswers,
        tu.ScoreRank,
        tu.ViewRank,
        tu.RepRank,
        CASE 
            WHEN tu.TotalPosts > 0 THEN 
                COALESCE(tu.TotalScore, 0) * 1.0 / tu.TotalPosts
            ELSE 0 
        END as EfficiencyScore,
        CASE 
            WHEN tu.RecentPosts > 0 THEN 
                COALESCE(tu.TotalScore, 0) * 1.0 / tu.RecentPosts
            ELSE 0 
        END as RecentEfficiency,
        CASE 
            WHEN tu.Reputation > 10000 THEN 'High'
            WHEN tu.Reputation > 1000 THEN 'Medium'
            WHEN tu.Reputation > 100 THEN 'Low'
            ELSE 'Beginner'
        END as RepLevel,
        CASE 
            WHEN tu.TotalPosts > 100 THEN 'Active'
            WHEN tu.TotalPosts > 10 THEN 'Regular'
            WHEN tu.TotalPosts > 0 THEN 'Occasional'
            ELSE 'Inactive'
        END as ActivityLevel,
        COALESCE((SELECT COUNT(*) FROM Posts p WHERE p.PostTypeId = 1 AND p.OwnerUserId = tu.UserId AND p.CreationDate >= CURRENT_DATE - INTERVAL '30 days'), 0) as RecentQuestionsThisMonth,
        COALESCE((SELECT COUNT(*) FROM Posts p WHERE p.PostTypeId = 2 AND p.OwnerUserId = tu.UserId AND p.CreationDate >= CURRENT_DATE - INTERVAL '30 days'), 0) as RecentAnswersThisMonth,
        COALESCE((SELECT AVG(COALESCE(p.Score, 0)) FROM Posts p WHERE p.OwnerUserId = tu.UserId AND p.CreationDate >= CURRENT_DATE - INTERVAL '30 days'), 0) as AvgRecentScore,
        COALESCE((SELECT AVG(COALESCE(p.Score, 0)) FROM Posts p WHERE p.OwnerUserId = tu.UserId AND p.PostTypeId = 1 AND p.CreationDate >= CURRENT_DATE - INTERVAL '30 days'), 0) as AvgRecentQuestionScore,
        COALESCE((SELECT AVG(COALESCE(p.Score, 0)) FROM Posts p WHERE p.OwnerUserId = tu.UserId AND p.PostTypeId = 2 AND p.CreationDate >= CURRENT_DATE - INTERVAL '30 days'), 0) as AvgRecentAnswerScore,
        COALESCE((SELECT COUNT(*) FROM Votes v JOIN Posts p ON v.PostId = p.Id WHERE v.UserId = tu.UserId AND v.VoteTypeId = 2), 0) as TotalUpvotesReceived,
        COALESCE((SELECT COUNT(*) FROM Votes v JOIN Posts p ON v.PostId = p.Id WHERE v.UserId = tu.UserId AND v.VoteTypeId = 3), 0) as TotalDownvotesReceived,
        COALESCE((SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = tu.UserId AND p.Score > 100), 0) as HighScorePosts,
        COALESCE((SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = tu.UserId AND p.Score > 500), 0) as VeryHighScorePosts
    FROM TopUsers tu
),
QualityPostFilter AS (
    SELECT 
        *,
        CASE 
            WHEN TotalScore >= 1000 THEN 'Excellent'
            WHEN TotalScore >= 500 THEN 'Good'
            WHEN TotalScore >= 100 THEN 'Fair'
            WHEN TotalScore >= 10 THEN 'Poor'
            ELSE 'Very Poor'
        END as QualityLevel,
        CASE 
            WHEN TotalViews >= 10000 THEN 'Highly Popular'
            WHEN TotalViews >= 5000 THEN 'Popular'
            WHEN TotalViews >= 1000 THEN 'Moderate'
            WHEN TotalViews >= 100 THEN 'Low'
            ELSE 'Very Low'
        END as PopularityLevel,
        CASE 
            WHEN EfficiencyScore >= 15 THEN 'Highly Efficient'
            WHEN EfficiencyScore >= 10 THEN 'Efficient'
            WHEN EfficiencyScore >= 5 THEN 'Moderate'
            ELSE 'Low'
        END as EfficiencyRating,
        CASE 
            WHEN AvgScorePerPost >= 10 THEN 'Excellent Poster'
            WHEN AvgScorePerPost >= 5 THEN 'Good Poster'
            WHEN AvgScorePerPost >= 1 THEN 'Average Poster'
            ELSE 'Poor Poster'
        END as PosterQuality,
        CASE 
            WHEN RecentEfficiency >= 15 THEN 'Highly Active Recently'
            WHEN RecentEfficiency >= 10 THEN 'Active Recently'
            WHEN RecentEfficiency >= 5 THEN 'Moderately Active Recently'
            ELSE 'Inactive Recently'
        END as RecentActivityRating
    FROM CombinedMetrics
),
ComplexPostAnalysis AS (
    SELECT 
        pp.PostId,
        pp.Title,
        pp.Body,
        pp.Score,
        pp.ViewCount,
        pp.CreationDate,
        pp.OwnerUserId,
        pp.TagsList,
        pp.TagCount,
        pp.PostType,
        pp.IsClosed,
        pp.IsCommunityOwned,
        pp.BodyPreview,
        pp.TitleLength,
        pp.BodyLength,
        pp.PostYear,
        pp.PostMonth,
        pp.PostDay,
        CASE 
            WHEN pp.PostMonth IN (12, 1, 2) THEN 'Winter'
            WHEN pp.PostMonth IN (3, 4, 5) THEN 'Spring'
            WHEN pp.PostMonth IN (6, 7, 8) THEN 'Summer'
            ELSE 'Autumn'
        END as Season,
        CASE 
            WHEN pp.BodyLength > 1000 THEN 'Long Post'
            WHEN pp.BodyLength > 500 THEN 'Medium Post'
            WHEN pp.BodyLength > 100 THEN 'Short Post'
            ELSE 'Very Short Post'
        END as PostLengthCategory,
        CASE 
            WHEN pp.Score >= 50 THEN 'Voted Highly'
            WHEN pp.Score >= 10 THEN 'Voted Moderately'
            WHEN pp.Score > 0 THEN 'Voted Somewhat'
            WHEN pp.Score < 0 THEN 'Downvoted'
            ELSE 'No Votes'
        END as ScoreCategory,
        CASE 
            WHEN pp.ViewCount >= 1000 THEN 'Highly Viewed'
            WHEN pp.ViewCount >= 100 THEN 'Moderately Viewed'
            WHEN pp.ViewCount >= 10 THEN 'Low Viewed'
            ELSE 'Very Low Viewed'
        END as ViewCategory,
        COALESCE((SELECT COUNT(*) FROM Comments c WHERE c.PostId = pp.PostId), 0) as CommentCount,
        COALESCE((SELECT COUNT(*) FROM Votes v WHERE v.PostId = pp.PostId AND v.VoteTypeId = 2), 0) as UpVotes,
        COALESCE((SELECT COUNT(*) FROM Votes v WHERE v.PostId = pp.PostId AND v.VoteTypeId = 3), 0) as DownVotes,
        COALESCE((SELECT COUNT(*) FROM Posts p WHERE p.ParentId = pp.PostId), 0) as AnswerCount,
        COALESCE((SELECT AVG(COALESCE(v.VoteTypeId, 0)) FROM Votes v WHERE v.PostId = pp.PostId), 0) as AvgVoteType,
        CASE 
            WHEN pp.TagsList IS NOT NULL AND LENGTH(pp.TagsList) > 0 THEN 
                REGEXP_REPLACE(pp.TagsList, '[^a-zA-Z0-9\s,]', '', 'g')
            ELSE ''
        END as CleanedTags,
        COALESCE((SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' || pp.TagsList || '%' AND p.Id != pp.PostId), 0) as SimilarPosts,
        LAG(pp.Score, 1) OVER (ORDER BY pp.CreationDate) as PreviousScore,
        LEAD(pp.Score, 1) OVER (ORDER BY pp.CreationDate) as NextScore,
        AVG(pp.Score) OVER (ORDER BY pp.CreationDate ROWS BETWEEN 10 PRECEDING AND CURRENT ROW) as MovingAverageScore,
        ROW_NUMBER() OVER (ORDER BY pp.Score DESC) as ScoreRank,
        RANK() OVER (ORDER BY pp.ViewCount DESC) as ViewRank,
        DENSE_RANK() OVER (ORDER BY pp.TitleLength DESC) as TitleLengthRank,
        PERCENT_RANK() OVER (ORDER BY pp.Score) as ScorePercentile,
        CUME_DIST() OVER (ORDER BY pp.Score) as ScoreCumulativeDistribution,
        NTILE(4) OVER (ORDER BY pp.Score) as ScoreQuartile
    FROM PostTagAnalytics pp
    WHERE pp.PostId IS NOT NULL
),
ComprehensiveAnalysis AS (
    SELECT 
        COALESCE(qp.UserId, cp.UserId) as AnalysisUserId,
        COALESCE(qp.DisplayName, cp.DisplayName) as AnalysisDisplayName,
        COALESCE(qp.Reputation, cp.Reputation) as AnalysisReputation,
        COALESCE(qp.Views, cp.Views) as AnalysisViews,
        COALESCE(qp.UpVotes, cp.UpVotes) as AnalysisUpVotes,
        COALESCE(qp.DownVotes, cp.DownVotes) as AnalysisDownVotes,
        COALESCE(qp.TotalPosts, cp.TotalPosts) as AnalysisTotalPosts,
        COALESCE(qp.Questions, cp.Questions) as AnalysisQuestions,
        COALESCE(qp.Answers, cp.Answers) as AnalysisAnswers,
        COALESCE(qp.Comments, cp.Comments) as AnalysisComments,
        COALESCE(qp.Badges, cp.Badges) as AnalysisBadges,
        COALESCE(qp.LastPostDate, cp.LastPostDate) as AnalysisLastPostDate,
        COALESCE(qp.LastCommentDate, cp.LastCommentDate) as AnalysisLastCommentDate,
        COALESCE(qp.ReputationRank, cp.ReputationRank) as AnalysisReputationRank,
        COALESCE(qp.PostActivityRank, cp.PostActivityRank) as AnalysisPostActivityRank,
        COALESCE(qp.TotalScore, cp.TotalScore) as AnalysisTotalScore,
        COALESCE(qp.TotalViews, cp.TotalViews) as AnalysisTotalViews,
        COALESCE(qp.AvgScorePerPost, cp.AvgScorePerPost) as AnalysisAvgScorePerPost,
        COALESCE(qp.AvgScorePerQuestion, cp.AvgScorePerQuestion) as AnalysisAvgScorePerQuestion,
        COALESCE(qp.AvgScorePerAnswer, cp.AvgScorePerAnswer) as AnalysisAvgScorePerAnswer,
        COALESCE(qp.RecentPosts, cp.RecentPosts) as AnalysisRecentPosts,
        COALESCE(qp.RecentQuestions, cp.RecentQuestions) as AnalysisRecentQuestions,
        COALESCE(qp.RecentAnswers, cp.RecentAnswers) as AnalysisRecentAnswers,
        COALESCE(qp.ScoreRank, cp.ScoreRank) as AnalysisScoreRank,
        COALESCE(qp.ViewRank, cp.ViewRank) as AnalysisViewRank,
        COALESCE(qp.RepRank, cp.RepRank) as AnalysisRepRank,
        COALESCE(qp.EfficiencyScore, cp.EfficiencyScore) as AnalysisEfficiencyScore,
        COALESCE(qp.RecentEfficiency, cp.RecentEfficiency) as AnalysisRecentEfficiency,
        COALESCE(qp.RepLevel, cp.RepLevel) as AnalysisRepLevel,
        COALESCE(qp.ActivityLevel, cp.ActivityLevel) as AnalysisActivityLevel,
        COALESCE(qp.RecentQuestionsThisMonth, cp.RecentQuestionsThisMonth) as AnalysisRecentQuestionsThisMonth,
        COALESCE(qp.RecentAnswersThisMonth, cp.RecentAnswersThisMonth) as AnalysisRecentAnswersThisMonth,
        COALESCE(qp.AvgRecentScore, cp.AvgRecentScore) as AnalysisAvgRecentScore,
        COALESCE(qp.AvgRecentQuestionScore, cp.AvgRecentQuestionScore) as AnalysisAvgRecentQuestionScore,
        COALESCE(qp.AvgRecentAnswerScore, cp.AvgRecentAnswerScore) as AnalysisAvgRecentAnswerScore,
        COALESCE(qp.TotalUpvotesReceived, cp.TotalUpvotesReceived) as AnalysisTotalUpvotesReceived,
        COALESCE(qp.TotalDownvotesReceived, cp.TotalDownvotesReceived) as AnalysisTotalDownvotesReceived,
        COALESCE(qp.HighScorePosts, cp.HighScorePosts) as AnalysisHighScorePosts,
        COALESCE(qp.VeryHighScorePosts, cp.VeryHighScorePosts) as AnalysisVeryHighScorePosts,
        COALESCE(qp.QualityLevel, cp.QualityLevel) as AnalysisQualityLevel,
        COALESCE(qp.PopularityLevel, cp.PopularityLevel) as AnalysisPopularityLevel,
        COALESCE(qp.EfficiencyRating, cp.EfficiencyRating) as AnalysisEfficiencyRating,
        COALESCE(qp.PosterQuality, cp.PosterQuality) as AnalysisPosterQuality,
        COALESCE(qp.RecentActivityRating, cp.RecentActivityRating) as AnalysisRecentActivityRating,
        ca.PostId,
        ca.Title,
        ca.Body,
        ca.Score,
        ca.ViewCount,
        ca.CreationDate,
        ca.TagsList,
        ca.TagCount,
        ca.PostType,
        ca.IsClosed,
        ca.IsCommunityOwned,
        ca.BodyPreview,
        ca.TitleLength,
        ca.BodyLength,
        ca.PostYear,
        ca.PostMonth,
        ca.PostDay,
        ca.Season,
        ca.PostLengthCategory,
        ca.ScoreCategory,
        ca.ViewCategory,
        ca.CommentCount,
        ca.UpVotes,
        ca.DownVotes,
        ca.AnswerCount,
        ca.AvgVoteType,
        ca.CleanedTags,
        ca.SimilarPosts,
        ca.PreviousScore,
        ca.NextScore,
        ca.MovingAverageScore,
        ca.ScoreRank,
        ca.ViewRank,
        ca.TitleLengthRank,
        ca.ScorePercentile,
        ca.ScoreCumulativeDistribution,
        ca.ScoreQuartile,
        CASE 
            WHEN ca.Score > 100 AND ca.ViewCount > 1000 THEN 'Exceptional Post'
            WHEN ca.Score > 50 AND ca.ViewCount > 500 THEN 'Good Post'
            WHEN ca.Score > 10 AND ca.ViewCount > 100 THEN 'Average Post'
            ELSE 'Below Average Post'
        END as PostQualityRating,
        CASE 
            WHEN ca.Score > 50 THEN 'Highly Valued'
            WHEN ca.Score > 10 THEN 'Valued'
            WHEN ca.Score > 0 THEN 'Moderately Valued'
            ELSE 'Unvalued'
        END as ValueRating,
        CASE 
            WHEN ca.ViewCount > 1000 THEN 'Popular'
            WHEN ca.ViewCount > 500 THEN 'Moderately Popular'
            WHEN ca.ViewCount > 100 THEN 'Minor Popular'
            ELSE 'Low Popularity'
        END as PopularityRating,
        CASE 
            WHEN ca.MovingAverageScore > 50 THEN 'Above Trend'
            WHEN ca.MovingAverageScore > 10 THEN 'In Trend'
            WHEN ca.MovingAverageScore > 0 THEN 'Below Trend'
            ELSE 'Significantly Below Trend'
        END as TrendRating,
        COALESCE((SELECT STRING_AGG(t.Name, ', ') FROM Posts p JOIN PostHistory ph ON p.Id = ph.PostId JOIN PostHistoryTypes t ON ph.PostHistoryTypeId = t.Id WHERE p.Id = ca.PostId), '') as PostHistoryTypes,
        COALESCE((SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = ca.PostId OR pl.RelatedPostId = ca.PostId), 0) as LinkCount,
        COALESCE((SELECT COUNT(*) FROM Votes v WHERE v.PostId = ca.PostId AND v.VoteTypeId = 1), 0) as AcceptanceCount,
        COALESCE((SELECT COUNT(*) FROM Votes v WHERE v.PostId = ca.PostId AND v.VoteTypeId = 5), 0) as FavoriteCount,
        COALESCE((SELECT STRING_AGG(b.Name, ', ') FROM Badges b WHERE b.UserId = COALESCE(qp.UserId, cp.UserId)), '') as UserBadges
    FROM QualityPostFilter qp
    FULL OUTER JOIN ComplexPostAnalysis ca ON qp.UserId IS NOT NULL OR ca.PostId IS NOT NULL
    LEFT JOIN Users cp ON ca.OwnerUserId = cp.Id
    WHERE (qp.UserId IS NOT NULL OR ca.PostId IS NOT NULL)
),
AggregatedMetrics AS (
    SELECT 
        AnalysisUserId,
        AnalysisDisplayName,
        AnalysisReputation,
        AnalysisViews,
        AnalysisUpVotes,
        AnalysisDownVotes,
        AnalysisTotalPosts,
        AnalysisQuestions,
        AnalysisAnswers,
        AnalysisComments,
        AnalysisBadges,
        AnalysisLastPostDate,
        AnalysisLastCommentDate,
        AnalysisReputationRank,
        AnalysisPostActivityRank,
        AnalysisTotalScore,
        AnalysisTotalViews,
        AnalysisAvgScorePerPost,
        AnalysisAvgScorePerQuestion,
        AnalysisAvgScorePerAnswer,
        AnalysisRecentPosts,
        AnalysisRecentQuestions,
        AnalysisRecentAnswers,
        AnalysisScoreRank,
        AnalysisViewRank,
        AnalysisRepRank,
        AnalysisEfficiencyScore,
        AnalysisRecentEfficiency,
        AnalysisRepLevel,
        AnalysisActivityLevel,
        AnalysisRecentQuestionsThisMonth,
        AnalysisRecentAnswersThisMonth,
        AnalysisAvgRecentScore,
        AnalysisAvgRecentQuestionScore,
        AnalysisAvgRecentAnswerScore,
        AnalysisTotalUpvotesReceived,
        AnalysisTotalDownvotesReceived,
        AnalysisHighScorePosts,
        AnalysisVeryHighScorePosts,
        AnalysisQualityLevel,
        AnalysisPopularityLevel,
        AnalysisEfficiencyRating,
        AnalysisPosterQuality,
        AnalysisRecentActivityRating,
        COUNT(*) as RecordCount,
        AVG(AnalysisTotalScore) as AvgTotalScore,
        AVG(AnalysisTotalViews) as AvgTotalViews,
        AVG(AnalysisAvgScorePerPost) as AvgAvgScorePerPost,
        SUM(AnalysisRecentPosts) as SumRecentPosts,
        MAX(AnalysisRecentQuestions) as MaxRecentQuestions,
        MIN(AnalysisRecentAnswers) as MinRecentAnswers,
        COUNT(DISTINCT AnalysisUserId) as DistinctUsers,
        COUNT(DISTINCT AnalysisDisplayName) as DistinctDisplayNames,
        GROUP_CONCAT(DISTINCT AnalysisQualityLevel) as DistinctQualityLevels,
        GROUP_CONCAT(DISTINCT AnalysisActivityLevel) as DistinctActivityLevels,
        COUNT(CASE WHEN AnalysisTotalScore > 1000 THEN 1 END) as HighScoringPosts,
        COUNT(CASE WHEN AnalysisTotalViews > 10000 THEN 1 END) as HighlyViewedPosts,
        SUM(CASE WHEN AnalysisScorePercentile > 0.75 THEN 1 ELSE 0 END) as TopQuarterPosts,
        AVG(CASE WHEN AnalysisScoreQuartile = 4 THEN 1 ELSE 0 END) as PctFourthQuartile,
        STRING_AGG(CASE WHEN AnalysisTotalScore > 100 THEN AnalysisDisplayName ELSE NULL END, ', ') as TopScorers,
        STRING_AGG(CASE WHEN AnalysisTotalViews > 1000 THEN AnalysisDisplayName ELSE NULL END, ', ') as TopViewers
    FROM ComprehensiveAnalysis
    GROUP BY AnalysisUserId, AnalysisDisplayName, AnalysisReputation, AnalysisViews, AnalysisUpVotes, AnalysisDownVotes, AnalysisTotalPosts, AnalysisQuestions, AnalysisAnswers, AnalysisComments, AnalysisBadges, AnalysisLastPostDate, AnalysisLastCommentDate, AnalysisReputationRank, AnalysisPostActivityRank, AnalysisTotalScore, AnalysisTotalViews, AnalysisAvgScorePerPost, AnalysisAvgScorePerQuestion, AnalysisAvgScorePerAnswer, AnalysisRecentPosts, AnalysisRecentQuestions, AnalysisRecentAnswers, AnalysisScoreRank, AnalysisViewRank, AnalysisRepRank, AnalysisEfficiencyScore, AnalysisRecentEfficiency, AnalysisRepLevel, AnalysisActivityLevel, AnalysisRecentQuestionsThisMonth, AnalysisRecentAnswersThisMonth, AnalysisAvgRecentScore, AnalysisAvgRecentQuestionScore, AnalysisAvgRecentAnswerScore, AnalysisTotalUpvotesReceived, AnalysisTotalDownvotesReceived, AnalysisHighScorePosts, AnalysisVeryHighScorePosts, AnalysisQualityLevel, AnalysisPopularityLevel, AnalysisEfficiencyRating, AnalysisPosterQuality, AnalysisRecentActivityRating
)
SELECT 
    AnalysisUserId,
    AnalysisDisplayName,
    AnalysisReputation,
    AnalysisViews,
    AnalysisUpVotes,
    AnalysisDownVotes,
    AnalysisTotalPosts,
    AnalysisQuestions,
    AnalysisAnswers,
    AnalysisComments,
    AnalysisBadges,
    AnalysisLastPostDate,
    AnalysisLastCommentDate,
    AnalysisReputationRank,
    AnalysisPostActivityRank,
    AnalysisTotalScore,
    AnalysisTotalViews,
    AnalysisAvgScorePerPost,
    AnalysisAvgScorePerQuestion,
    AnalysisAvgScorePerAnswer,
    AnalysisRecentPosts,
    AnalysisRecentQuestions,
    AnalysisRecentAnswers,
    AnalysisScoreRank,
    AnalysisViewRank,
    AnalysisRepRank,
    AnalysisEfficiencyScore,
    AnalysisRecentEfficiency,
    AnalysisRepLevel,
    AnalysisActivityLevel,
    AnalysisRecentQuestionsThisMonth,
    AnalysisRecentAnswersThisMonth,
    AnalysisAvgRecentScore,
    AnalysisAvgRecentQuestionScore,
    AnalysisAvgRecentAnswerScore,
    AnalysisTotalUpvotesReceived,
    AnalysisTotalDownvotesReceived,
    AnalysisHighScorePosts,
    AnalysisVeryHighScorePosts,
    AnalysisQualityLevel,
    AnalysisPopularityLevel,
    AnalysisEfficiencyRating,
    AnalysisPosterQuality,
    AnalysisRecentActivityRating,
    RecordCount,
    AvgTotalScore,
    AvgTotalViews,
    AvgAvgScorePerPost,
    SumRecentPosts,
    MaxRecentQuestions,
    MinRecentAnswers,
    DistinctUsers,
    DistinctDisplayNames,
    DistinctQualityLevels,
    DistinctActivityLevels,
    HighScoringPosts,
    HighlyViewedPosts,
    TopQuarterPosts,
    PctFourthQuartile,
    TopScorers,
    TopViewers,
    CASE 
        WHEN AnalysisReputation > 50000 THEN 'Elite'
        WHEN AnalysisReputation > 10000 THEN 'Master'
        WHEN AnalysisReputation > 1000 THEN 'Expert'
        WHEN AnalysisReputation > 100 THEN 'Novice'
        ELSE 'Beginner'
    END as UserTier,
    CASE 
        WHEN AnalysisTotalPosts > 1000 THEN 'Legendary Contributor'
        WHEN AnalysisTotalPosts > 100 THEN 'Active Contributor'
        WHEN AnalysisTotalPosts > 10 THEN 'Regular Contributor'
        ELSE 'Occasional Contributor'
    END as ContributionTier,
    CASE 
        WHEN AnalysisTotalScore > 10000 THEN 'Top Performer'
        WHEN AnalysisTotalScore > 5000 THEN 'High Performer'
        WHEN AnalysisTotalScore > 1000 THEN 'Moderate Performer'
        ELSE 'Average Performer'
    END as PerformanceTier,
    CASE 
        WHEN AnalysisTotalViews > 100000 THEN 'Viral Contributor'
        WHEN AnalysisTotalViews > 10000 THEN 'Popular Contributor'
        WHEN AnalysisTotalViews > 1000 THEN 'Known Contributor'
        ELSE 'Unknown Contributor'
    END as PopularityTier,
    CASE 
        WHEN AnalysisEfficiencyScore > 15 THEN 'Exceptional Efficiency'
        WHEN AnalysisEfficiencyScore > 10 THEN 'High Efficiency'
        WHEN AnalysisEfficiencyScore > 5 THEN 'Moderate Efficiency'
        ELSE 'Low Efficiency'
    END as EfficiencyTier,
    CASE 
        WHEN AnalysisAvgScorePerPost > 20 THEN 'Highly Scoring'
        WHEN AnalysisAvgScorePerPost > 10 THEN 'Moderately Scoring'
        WHEN AnalysisAvgScorePerPost > 5 THEN 'Average Scoring'
        ELSE 'Low Scoring'
    END as ScoringTier,
    CASE 
        WHEN AnalysisAvgRecentScore > 15 THEN 'Highly Active'
        WHEN AnalysisAvgRecentScore > 10 THEN 'Moderately Active'
        WHEN AnalysisAvgRecentScore > 5 THEN 'Somewhat Active'
        ELSE 'Inactive'
    END as ActivityTier,
    CASE 
        WHEN AnalysisRecentPosts > 50 THEN 'Very Active'
        WHEN AnalysisRecentPosts > 25 THEN 'Active'
        WHEN AnalysisRecentPosts > 10 THEN 'Moderately Active'
        ELSE 'Less Active'
    END as RecentActivityTier,
    CASE 
        WHEN AnalysisHighScorePosts > 20 THEN 'High Scorer'
        WHEN AnalysisHighScorePosts > 10 THEN 'Moderate Scorer'
        WHEN AnalysisHighScorePosts > 5 THEN 'Average Scorer'
        ELSE 'Below Average Scorer'
    END as HighScoreTier,
    CASE 
        WHEN AnalysisVeryHighScorePosts > 5 THEN 'Very High Scorer'
        WHEN AnalysisVeryHighScorePosts > 2 THEN 'Moderate High Scorer'
        ELSE 'Regular Scorer'
    END as VeryHighScoreTier,
    CASE 
        WHEN AnalysisTotalUpvotesReceived > 500 THEN 'Highly Upvoted'
        WHEN AnalysisTotalUpvotesReceived > 200 THEN 'Moderately Upvoted'
        WHEN AnalysisTotalUpvotesReceived > 50 THEN 'Some Upvotes'
        ELSE 'Few Upvotes'
    END as UPVOTE_TIER,
    CASE 
        WHEN AnalysisTotalDownvotesReceived > 100 THEN 'Highly Downvoted'
        WHEN AnalysisTotalDownvotesReceived > 50 THEN 'Moderately Downvoted'
        WHEN AnalysisTotalDownvotesReceived > 10 THEN 'Some Downvotes'
        ELSE 'Few Downvotes'
    END as DOWNVOTE_TIER,
    CASE 
        WHEN (AnalysisTotalUpvotesReceived - AnalysisTotalDownvotesReceived) > 1000 THEN 'Extreme Positive Rating'
        WHEN (AnalysisTotalUpvotesReceived - AnalysisTotalDownvotesReceived) > 500 THEN 'High Positive Rating'
        WHEN (AnalysisTotalUpvotesReceived - AnalysisTotalDownvotesReceived) > 100 THEN 'Positive Rating'
        WHEN (AnalysisTotalUpvotesReceived - AnalysisTotalDownvotesReceived) > 0 THEN 'Slightly Positive Rating'
        WHEN (AnalysisTotalUpvotesReceived - AnalysisTotalDownvotesReceived) = 0 THEN 'Neutral Rating'
        WHEN (AnalysisTotalUpvotesReceived - AnalysisTotalDownvotesReceived) < -100 THEN 'Negative Rating'
        ELSE 'Extreme Negative Rating'
    END as NetRating,
    ROW_NUMBER() OVER (ORDER BY AnalysisTotalScore DESC, AnalysisTotalViews DESC) as OverallRank,
    DENSE_RANK() OVER (ORDER BY AnalysisReputation DESC) as ReputationRankOverall,
    RANK() OVER (ORDER BY AnalysisTotalPosts DESC) as PostRank,
    PERCENT_RANK() OVER (ORDER BY AnalysisTotalScore) as ScorePercentileOverall,
    CUME_DIST() OVER (ORDER BY AnalysisTotalViews) as ViewCumeDist,
    NTILE(100) OVER (ORDER BY AnalysisTotalScore) as ScorePercentileBucket
FROM AggregatedMetrics
ORDER BY AnalysisTotalScore DESC, AnalysisTotalViews DESC
LIMIT 1000 OFFSET 0;
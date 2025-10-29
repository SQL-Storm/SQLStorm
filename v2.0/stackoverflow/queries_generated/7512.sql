-- {"query": "7512.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2553} 
WITH PostStats AS (
    SELECT 
        p.Id as PostId,
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
        p.Body,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostType,
        DENSE_RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) as ScoreRank,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) as RecentPostId,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) as UserPostCount,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as UserAvgScore,
        LAG(p.Score, 1) OVER (ORDER BY p.CreationDate) as PrevScore,
        LEAD(p.Score, 1) OVER (ORDER BY p.CreationDate) as NextScore,
        NTILE(4) OVER (ORDER BY p.Score) as ScoreQuartile
    FROM Posts p
    WHERE p.Score IS NOT NULL
),
UserActivity AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.DisplayName,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.CreationDate as UserCreationDate,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        AVG(p.Score) as AvgPostScore,
        MAX(p.CreationDate) as LastPostDate,
        DATEDIFF(CURRENT_TIMESTAMP, u.CreationDate) as AccountAgeDays,
        CASE 
            WHEN u.Reputation >= 10000 THEN 'Elite'
            WHEN u.Reputation >= 1000 THEN 'Advanced'
            WHEN u.Reputation >= 100 THEN 'Intermediate'
            ELSE 'Beginner'
        END as ReputationTier,
        COALESCE(
            (SELECT STRING_AGG(DISTINCT t.TagName, ', ')
             FROM Posts p2
             JOIN Tags t ON p2.Tags LIKE '%' || t.TagName || '%'
             WHERE p2.OwnerUserId = u.Id
             GROUP BY p2.OwnerUserId), '') as UserTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes, u.CreationDate
),
TagStats AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE WHEN t.IsRequired = 1 THEN 'Required' ELSE 'Optional' END as TagType,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            WHEN t.Count > 10 THEN 'Niche'
            ELSE 'Rare'
        END as PopularityLevel,
        RANK() OVER (ORDER BY t.Count DESC) as TagRank,
        AVG(t.Count) OVER () as AvgTagCount
    FROM Tags t
),
PerformanceMetrics AS (
    SELECT 
        ps.PostId,
        ps.PostTypeId,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.ScoreRank,
        ps.RecentPostId,
        ps.UserPostCount,
        ps.UserAvgScore,
        ps.PrevScore,
        ps.NextScore,
        ps.ScoreQuartile,
        ps.Title,
        ps.Tags,
        ps.Body,
        ps.PostType,
        ua.UserId,
        ua.Reputation,
        ua.DisplayName,
        ua.PostCount,
        ua.CommentCount,
        ua.BadgeCount,
        ua.AvgPostScore,
        ua.LastPostDate,
        ua.AccountAgeDays,
        ua.ReputationTier,
        ua.UserTags,
        ts.TagName,
        ts.Count as TagCount,
        ts.TagType,
        ts.PopularityLevel,
        ts.TagRank,
        ts.AvgTagCount,
        CASE 
            WHEN ps.Score > (SELECT AVG(Score) FROM Posts) THEN 'AboveAverage'
            WHEN ps.Score < (SELECT AVG(Score) FROM Posts) THEN 'BelowAverage'
            ELSE 'Average'
        END as ScorePerformance,
        CASE 
            WHEN ps.ViewCount > (SELECT AVG(ViewCount) FROM Posts) THEN 'HighView'
            WHEN ps.ViewCount < (SELECT AVG(ViewCount) FROM Posts) THEN 'LowView'
            ELSE 'NormalView'
        END as ViewPerformance,
        CASE 
            WHEN ps.UserAvgScore > (SELECT AVG(AvgPostScore) FROM UserActivity) THEN 'HighUserPerformance'
            WHEN ps.UserAvgScore < (SELECT AVG(AvgPostScore) FROM UserActivity) THEN 'LowUserPerformance'
            ELSE 'AverageUserPerformance'
        END as UserPerformance,
        ROW_NUMBER() OVER (PARTITION BY ps.OwnerUserId ORDER BY ps.CreationDate DESC) as UserRecentPost,
        ROW_NUMBER() OVER (ORDER BY ps.ViewCount DESC) as PopularPostRank,
        CASE 
            WHEN ps.AnswerCount > 0 AND ps.AnswerCount < 5 THEN 'FewAnswers'
            WHEN ps.AnswerCount >= 5 AND ps.AnswerCount < 10 THEN 'ModerateAnswers'
            WHEN ps.AnswerCount >= 10 THEN 'ManyAnswers'
            ELSE 'NoAnswer'
        END as AnswerLevel,
        DATEDIFF(CURRENT_TIMESTAMP, ps.CreationDate) as PostAgeDays,
        LAG(ps.CreationDate, 1) OVER (ORDER BY ps.CreationDate) as PrevPostDate,
        LEAD(ps.CreationDate, 1) OVER (ORDER BY ps.CreationDate) as NextPostDate,
        ABS(ps.Score - COALESCE(ps.PrevScore, ps.Score)) as ScoreChange,
        CASE 
            WHEN ps.PostTypeId = 1 THEN 
                CASE WHEN ps.AnswerCount > 0 THEN 'HasAnswers' ELSE 'NoAnswers' END
            ELSE 'NotQuestion'
        END as QuestionStatus
    FROM PostStats ps
    LEFT JOIN UserActivity ua ON ps.OwnerUserId = ua.UserId
    LEFT JOIN TagStats ts ON ps.Tags LIKE '%' || ts.TagName || '%'
    WHERE ps.PostTypeId IN (1, 2)
),
ComplexCalculations AS (
    SELECT 
        pm.*,
        (pm.ViewCount * 0.1 + pm.Score * 0.3 + pm.AnswerCount * 0.2 + pm.CommentCount * 0.2 + pm.FavoriteCount * 0.2) as WeightedScore,
        CASE 
            WHEN pm.Reputation > 10000 THEN 'HighRep'
            WHEN pm.Reputation > 1000 THEN 'MediumRep'
            WHEN pm.Reputation > 100 THEN 'LowRep'
            ELSE 'VeryLowRep'
        END as ReputationGroup,
        CASE 
            WHEN pm.PostAgeDays > 365 THEN 'LongTerm'
            WHEN pm.PostAgeDays > 90 THEN 'MediumTerm'
            WHEN pm.PostAgeDays > 30 THEN 'ShortTerm'
            ELSE 'New'
        END as PostAgeGroup,
        CASE 
            WHEN pm.PostType = 'Question' AND pm.AnswerCount = 0 THEN 'Unanswered'
            WHEN pm.PostType = 'Question' AND pm.AnswerCount > 0 THEN 'Answered'
            ELSE 'NotQuestion'
        END as QuestionResolution,
        COALESCE(pm.CommentCount, 0) + COALESCE(pm.AnswerCount, 0) as EngagementCount,
        CASE 
            WHEN pm.ScoreQuartile = 1 THEN 'TopQuartile'
            WHEN pm.ScoreQuartile = 4 THEN 'BottomQuartile'
            ELSE 'MiddleQuartile'
        END as ScoreQuartileGroup,
        CASE 
            WHEN pm.ViewCount > pm.UserAvgScore THEN 'PopularPost'
            ELSE 'RegularPost'
        END as PostPopularity,
        ABS(pm.PostAgeDays - (SELECT AVG(PostAgeDays) FROM ComplexCalculations)) as AgeDeviation
    FROM PerformanceMetrics pm
    WHERE pm.Score IS NOT NULL AND pm.ViewCount IS NOT NULL
)
SELECT 
    cc.PostId,
    cc.PostType,
    cc.Title,
    cc.Tags,
    cc.Score,
    cc.ViewCount,
    cc.AnswerCount,
    cc.CommentCount,
    cc.FavoriteCount,
    cc.ReputationTier,
    cc.ReputationGroup,
    cc.PostAgeGroup,
    cc.QuestionStatus,
    cc.ScorePerformance,
    cc.ViewPerformance,
    cc.UserPerformance,
    cc.PopularPostRank,
    cc.WeightedScore,
    cc.EngagementCount,
    cc.ScoreQuartileGroup,
    cc.PostPopularity,
    cc.AgeDeviation,
    cc.UserTags,
    cc.TagName,
    cc.TagCount,
    cc.TagType,
    cc.PopularityLevel,
    cc.RecentPostId,
    cc.UserRecentPost,
    cc.AccountAgeDays,
    cc.UserAvgScore,
    cc.ScoreChange,
    cc.PostAgeDays,
    cc.PrevPostDate,
    cc.NextPostDate,
    cc.ScoreRank,
    cc.TagRank,
    cc.UserPostCount,
    cc.AvgTagCount,
    cc.LastPostDate,
    cc.BadgeCount,
    cc.CommentCount,
    CASE 
        WHEN cc.WeightedScore > (SELECT AVG(WeightedScore) FROM ComplexCalculations) THEN 'HighlyRated'
        WHEN cc.WeightedScore < (SELECT AVG(WeightedScore) FROM ComplexCalculations) THEN 'AverageRated'
        ELSE 'BelowAverageRated'
    END as RatingLevel,
    STRING_AGG(cc.TagName, ', ') OVER (PARTITION BY cc.UserId ORDER BY cc.TagCount DESC) as UserTagSummary,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = cc.UserId AND p.PostTypeId = 1 AND p.Score > 100) as HighScoreQuestions,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = cc.UserId AND p.PostTypeId = 2 AND p.Score > 100) as HighScoreAnswers,
    (SELECT AVG(ViewCount) FROM Posts p WHERE p.OwnerUserId = cc.UserId AND p.PostTypeId = 1) as UserQuestionAvgViews,
    (SELECT AVG(ViewCount) FROM Posts p WHERE p.OwnerUserId = cc.UserId AND p.PostTypeId = 2) as UserAnswerAvgViews,
    CASE 
        WHEN cc.AnswerLevel = 'ManyAnswers' AND cc.Score > 50 THEN 'HighValueQuestion'
        WHEN cc.AnswerLevel = 'FewAnswers' AND cc.Score < 10 THEN 'LowValueQuestion'
        ELSE 'RegularQuestion'
    END as QuestionValue,
    (SELECT MAX(p.Score) FROM Posts p WHERE p.OwnerUserId = cc.UserId AND p.PostTypeId = 1) as UserMaxQuestionScore,
    (SELECT MAX(p.Score) FROM Posts p WHERE p.OwnerUserId = cc.UserId AND p.PostTypeId = 2) as UserMaxAnswerScore
FROM ComplexCalculations cc
WHERE cc.PostId IS NOT NULL
  AND cc.Score > 0
  AND cc.ViewCount > 0
  AND cc.PostType IN ('Question', 'Answer')
  AND cc.ReputationTier IN ('Elite', 'Advanced', 'Intermediate')
  AND (cc.TagCount IS NULL OR cc.TagCount > 5)
  AND cc.PostAgeDays < 3650
  AND cc.UserAvgScore IS NOT NULL
  AND cc.WeightedScore IS NOT NULL
  AND cc.WeightedScore > (SELECT AVG(WeightedScore) FROM ComplexCalculations)
ORDER BY cc.WeightedScore DESC, cc.ViewCount DESC, cc.Score DESC
LIMIT 1000;
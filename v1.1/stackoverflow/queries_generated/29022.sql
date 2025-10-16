-- {"query": "29022.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2598} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        COUNT(DISTINCT c.Id) as Comments,
        COUNT(DISTINCT b.Id) as Badges,
        MAX(p.CreationDate) as LastPostDate,
        AVG(p.Score) as AvgPostScore,
        MAX(u.Views) as UserViews,
        CASE 
            WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0 
            THEN CAST(COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS FLOAT) / 
                 CAST(COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS FLOAT)
            ELSE 0 
        END as AnswerQuestionRatio
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2010-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views
),
PostAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.PostTypeId,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.Tags,
        CASE 
            WHEN p.PostTypeId = 1 THEN 
                CASE 
                    WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Answered'
                    WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
                    ELSE 'Unanswered'
                END
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostStatus,
        ABS(CAST(p.Score AS FLOAT) - (
            SELECT AVG(Score) 
            FROM Posts p2 
            WHERE p2.PostTypeId = p.PostTypeId 
            AND p2.CreationDate >= DATEADD(Month, -6, p.CreationDate)
            AND p2.CreationDate <= p.CreationDate
        )) as ScoreDeviationFromRecentAvg,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as PostRank,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PreviousScore
    FROM Posts p
    WHERE p.CreationDate >= '2015-01-01'
    AND p.Score IS NOT NULL
),
TagAnalysis AS (
    SELECT 
        t.Id as TagId,
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            ELSE 'Niche'
        END as TagPopularity,
        LAG(t.Count, 1) OVER (ORDER BY t.Count DESC) - t.Count as CountChangeFromPrevious
    FROM Tags t
    WHERE t.Count > 0
),
ComplexUserPerformance AS (
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
        uas.AvgPostScore,
        uas.UserViews,
        uas.AnswerQuestionRatio,
        CASE 
            WHEN uas.Reputation > 10000 AND uas.TotalPosts > 100 THEN 'Elite'
            WHEN uas.Reputation > 1000 AND uas.TotalPosts > 50 THEN 'Experienced'
            WHEN uas.Reputation > 100 AND uas.TotalPosts > 10 THEN 'Active'
            ELSE 'Casual'
        END as UserTier,
        CASE 
            WHEN uas.AnswerQuestionRatio > 2 AND uas.Reputation > 2000 THEN 'HighlyActiveAnswerer'
            WHEN uas.AnswerQuestionRatio > 1 AND uas.Reputation > 1500 THEN 'ActiveAnswerer'
            ELSE 'Regular'
        END as AnsweringStyle,
        ROW_NUMBER() OVER (ORDER BY uas.Reputation DESC, uas.TotalPosts DESC) as ReputationRank
    FROM UserActivityStats uas
    WHERE uas.Reputation > 0 AND uas.TotalPosts > 0
),
FinalAnalysis AS (
    SELECT 
        cu.UserId,
        cu.DisplayName,
        cu.Reputation,
        cu.TotalPosts,
        cu.Questions,
        cu.Answers,
        cu.Comments,
        cu.Badges,
        cu.LastPostDate,
        cu.AvgPostScore,
        cu.UserViews,
        cu.AnswerQuestionRatio,
        cu.UserTier,
        cu.AnsweringStyle,
        cu.ReputationRank,
        pa.PostId,
        pa.Title,
        pa.Score,
        pa.ViewCount,
        pa.CreationDate as PostCreationDate,
        pa.PostStatus,
        pa.ScoreDeviationFromRecentAvg,
        pa.PostRank,
        pa.PreviousScore,
        ta.TagId,
        ta.TagName,
        ta.TagCount,
        ta.TagPopularity,
        ta.CountChangeFromPrevious,
        CASE 
            WHEN pa.Score > 50 AND pa.ViewCount > 1000 THEN 'HighImpact'
            WHEN pa.Score > 20 AND pa.ViewCount > 500 THEN 'MediumImpact'
            ELSE 'LowImpact'
        END as PostImpact,
        CASE 
            WHEN pa.PostStatus = 'Answered' AND pa.AcceptedAnswerId IS NOT NULL THEN 'Accepted'
            WHEN pa.PostStatus = 'Closed' THEN 'Closed'
            WHEN pa.PostStatus = 'Answer' AND pa.Score > 10 THEN 'HighScoreAnswer'
            ELSE 'Other'
        END as PostCategory,
        DENSE_RANK() OVER (PARTITION BY pa.OwnerUserId ORDER BY pa.Score DESC) as ScoreRankPerUser,
        RANK() OVER (ORDER BY pa.Score DESC, pa.ViewCount DESC) as OverallScoreRank,
        LAG(pa.Score, 2) OVER (ORDER BY pa.CreationDate) as ScoreTwoPostsAgo,
        LAG(pa.ViewCount, 2) OVER (ORDER BY pa.CreationDate) as ViewCountTwoPostsAgo,
        ABS(pa.Score - COALESCE(pa.PreviousScore, 0)) as ScoreChangeFromPrevious,
        COALESCE(pa.Score / NULLIF(pa.ViewCount, 0), 0) as ScoreToViewRatio,
        CASE 
            WHEN pa.ScoreDeviationFromRecentAvg > 10 THEN 'AboveRecentAvg'
            WHEN pa.ScoreDeviationFromRecentAvg < -10 THEN 'BelowRecentAvg'
            ELSE 'NearRecentAvg'
        END as ScoreDeviationCategory,
        IIF(pa.Score >= 0, 'PositiveScore', 'NegativeScore') as ScoreCategory,
        CAST(COUNT(*) OVER () AS FLOAT) AS TotalRows,
        CAST(ROW_NUMBER() OVER (ORDER BY pa.Score DESC) AS FLOAT) AS RowNumber
    FROM ComplexUserPerformance cu
    LEFT JOIN PostAnalysis pa ON cu.UserId = pa.OwnerUserId
    LEFT JOIN TagAnalysis ta ON pa.Tags LIKE '%' + ta.TagName + '%'
    WHERE cu.TotalPosts > 0 AND pa.Score IS NOT NULL
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
    fa.LastPostDate,
    fa.AvgPostScore,
    fa.UserViews,
    fa.AnswerQuestionRatio,
    fa.UserTier,
    fa.AnsweringStyle,
    fa.ReputationRank,
    fa.PostId,
    fa.Title,
    fa.Score,
    fa.ViewCount,
    fa.PostCreationDate,
    fa.PostStatus,
    fa.ScoreDeviationFromRecentAvg,
    fa.PostRank,
    fa.PreviousScore,
    fa.TagId,
    fa.TagName,
    fa.TagCount,
    fa.TagPopularity,
    fa.CountChangeFromPrevious,
    fa.PostImpact,
    fa.PostCategory,
    fa.ScoreRankPerUser,
    fa.OverallScoreRank,
    fa.ScoreTwoPostsAgo,
    fa.ViewCountTwoPostsAgo,
    fa.ScoreChangeFromPrevious,
    fa.ScoreToViewRatio,
    fa.ScoreDeviationCategory,
    fa.ScoreCategory,
    fa.TotalRows,
    fa.RowNumber,
    ROUND((fa.RowNumber / NULLIF(fa.TotalRows, 0)) * 100, 2) as PercentileRank,
    CASE 
        WHEN fa.Score > (SELECT AVG(Score) FROM Posts WHERE CreationDate >= '2015-01-01') THEN 'AboveAvg'
        ELSE 'BelowAvg'
    END as ScorePosition,
    CASE 
        WHEN fa.ViewCount > (SELECT AVG(ViewCount) FROM Posts WHERE CreationDate >= '2015-01-01') THEN 'AboveAvgViews'
        ELSE 'BelowAvgViews'
    END as ViewPosition,
    CASE 
        WHEN fa.AnswerQuestionRatio > 1.5 THEN 'HighAnswerToQuestionRatio'
        WHEN fa.AnswerQuestionRatio > 0.5 THEN 'ModerateAnswerToQuestionRatio'
        ELSE 'LowAnswerToQuestionRatio'
    END as AnswerQuestionRatioCategory,
    IIF(fa.Reputation BETWEEN 1000 AND 10000, 'StandardReputation', 'SpecialReputation') as ReputationCategory,
    CASE 
        WHEN fa.UserTier = 'Elite' AND fa.PostImpact = 'HighImpact' THEN 'EliteHighImpact'
        WHEN fa.UserTier = 'Experienced' AND fa.PostImpact = 'MediumImpact' THEN 'ExperiencedMediumImpact'
        WHEN fa.UserTier = 'Active' AND fa.PostImpact = 'LowImpact' THEN 'ActiveLowImpact'
        ELSE 'StandardCategory'
    END as UserPostCategory,
    (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = fa.UserId AND PostTypeId = 1) as UserQuestionsCount,
    (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = fa.UserId AND PostTypeId = 2) as UserAnswersCount,
    (SELECT AVG(Score) FROM Posts WHERE OwnerUserId = fa.UserId AND PostTypeId = 1) as UserQuestionAvgScore,
    (SELECT AVG(Score) FROM Posts WHERE OwnerUserId = fa.UserId AND PostTypeId = 2) as UserAnswerAvgScore,
    (fa.ScoreChangeFromPrevious / NULLIF(fa.PreviousScore, 0)) * 100 as ScoreChangePercent,
    CASE 
        WHEN fa.TagName IS NULL THEN 'NoTags'
        WHEN fa.TagCount > 500 THEN 'PopularTag'
        ELSE 'RegularTag'
    END as TagCategory,
    'FinalAnalysis_' + CAST(fa.UserId AS VARCHAR(10)) + '_' + CAST(fa.PostId AS VARCHAR(10)) as AnalysisIdentifier,
    (fa.Reputation * fa.UserViews) / NULLIF(fa.TotalPosts, 0) as ReputationEffectivenessMetric
FROM FinalAnalysis fa
WHERE (
    fa.PostImpact IN ('HighImpact', 'MediumImpact') 
    OR fa.TagPopularity = 'Popular'
    OR fa.UserTier IN ('Elite', 'Experienced')
)
AND (
    fa.ScoreDeviationFromRecentAvg > 5 
    OR fa.AnswerQuestionRatio > 1.2
    OR fa.AvgPostScore > 5
)
AND (
    fa.Reputation > 2000
    OR fa.TotalPosts > 50
    OR fa.Badges > 10
)
ORDER BY fa.Reputation DESC, fa.Score DESC, fa.ViewCount DESC, fa.ReputationRank
OFFSET 0 ROWS
FETCH NEXT 1000 ROWS ONLY;
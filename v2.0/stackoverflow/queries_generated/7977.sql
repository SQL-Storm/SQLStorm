-- {"query": "7977.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2744} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.DisplayName,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id END) as Wikis,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        MAX(p.CreationDate) as LastPostDate,
        COUNT(DISTINCT b.Id) as Badges,
        COUNT(DISTINCT c.Id) as Comments,
        COUNT(DISTINCT v.Id) as Votes,
        COALESCE(AVG(CAST(p.Score AS FLOAT)), 0) as AvgPostScore,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2) FROM p WHERE p.Tags IS NOT NULL, ', ') as AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.Reputation, u.DisplayName
),
RankedUsers AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (ORDER BY TotalScore DESC, Reputation DESC) as ScoreRank,
        DENSE_RANK() OVER (ORDER BY TotalPosts DESC) as PostRank,
        RANK() OVER (ORDER BY Badges DESC) as BadgeRank,
        PERCENT_RANK() OVER (ORDER BY Reputation DESC) as ReputationPercentile,
        NTILE(10) OVER (ORDER BY TotalScore DESC) as PerformanceQuartile
    FROM UserActivityStats
),
TopUsers AS (
    SELECT *
    FROM RankedUsers
    WHERE ScoreRank <= 500 AND PostRank <= 1000
),
QuestionStats AS (
    SELECT 
        p.Id as QuestionId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Tags,
        CASE 
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Yes' 
            ELSE 'No' 
        END as HasAcceptedAnswer,
        DATEDIFF(day, p.CreationDate, COALESCE(p.ClosedDate, CURRENT_TIMESTAMP)) as DaysOpen,
        COALESCE(p.FavoriteCount, 0) as FavoriteCount,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2) FROM p WHERE p.Tags IS NOT NULL, ', ') as QuestionTags,
        COUNT(p.Id) OVER (PARTITION BY p.OwnerUserId) as UserQuestionCount,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as UserAvgScore,
        LAG(p.Score) OVER (ORDER BY p.Score DESC) as NextHigherScore,
        LEAD(p.Score) OVER (ORDER BY p.Score ASC) as NextLowerScore,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as RecentPostOrder,
        CASE 
            WHEN p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'AboveAverage' 
            ELSE 'BelowAverage' 
        END as ScoreCategory,
        CASE 
            WHEN p.AnswerCount > 10 THEN 'HighlyAnswered' 
            WHEN p.AnswerCount > 0 THEN 'Answered' 
            ELSE 'Unanswered' 
        END as AnswerStatus,
        COALESCE(COUNT(DISTINCT v.Id), 0) as VoteCount,
        COALESCE(COUNT(DISTINCT c.Id), 0) as CommentCountOnQuestion
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.PostTypeId = 1
),
AnswerStats AS (
    SELECT 
        p.Id as AnswerId,
        p.ParentId as QuestionId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Body,
        COALESCE(p.FavoriteCount, 0) as FavoriteCount,
        DATEDIFF(day, p.CreationDate, CURRENT_TIMESTAMP) as DaysOld,
        CASE 
            WHEN DATEDIFF(day, p.CreationDate, CURRENT_TIMESTAMP) < 30 THEN 'New'
            WHEN DATEDIFF(day, p.CreationDate, CURRENT_TIMESTAMP) < 365 THEN 'Recent'
            ELSE 'Old'
        END as AgeCategory,
        ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC) as RankingInQuestion,
        PERCENT_RANK() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC) as ScorePercentileInQuestion,
        LAG(p.Score) OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC) as PreviousAnswerScore
    FROM Posts p
    WHERE p.PostTypeId = 2
),
ComplexAnalysis AS (
    SELECT 
        tu.UserId,
        tu.DisplayName,
        tu.Reputation,
        tu.TotalPosts,
        tu.Questions,
        tu.Answers,
        tu.Wikis,
        tu.TotalScore,
        tu.Badges,
        tu.AvgPostScore,
        tu.ReputationPercentile,
        tu.PerformanceQuartile,
        qs.QuestionId,
        qs.Title,
        qs.Score as QuestionScore,
        qs.ViewCount,
        qs.AnswerCount,
        qs.CommentCount,
        qs.HasAcceptedAnswer,
        qs.DaysOpen,
        qs.FavoriteCount,
        qs.QuestionTags,
        qs.ScoreCategory,
        qs.AnswerStatus,
        qs.VoteCount,
        qs.CommentCountOnQuestion,
        asa.AnswerId,
        asa.Score as AnswerScore,
        asa.ViewCount as AnswerViewCount,
        asa.RankingInQuestion,
        asa.ScorePercentileInQuestion,
        asa.AgeCategory,
        asa.PreviousAnswerScore,
        CASE 
            WHEN asa.Score > qs.Score THEN 'HigherThanQuestion'
            WHEN asa.Score < qs.Score THEN 'LowerThanQuestion'
            ELSE 'SameAsQuestion'
        END as AnswerScoreVsQuestion,
        CASE 
            WHEN asa.RankingInQuestion = 1 AND qs.HasAcceptedAnswer = 'Yes' THEN 'BestAnswerWithAccept'
            WHEN asa.RankingInQuestion = 1 AND qs.HasAcceptedAnswer = 'No' THEN 'BestAnswerNoAccept'
            ELSE 'RegularAnswer'
        END as AnswerType,
        CASE 
            WHEN qs.DaysOpen > 0 AND (qs.Score * 1.0 / qs.DaysOpen) > 0.5 THEN 'ActiveQuestion'
            ELSE 'InactiveQuestion'
        END as QuestionEngagementStatus,
        COALESCE(
            NULLIF(
                (CAST(asa.Score as FLOAT) / NULLIF(qs.Score, 0)) * 100, 
                0
            ), 
            0
        ) as AnswerScorePercentage,
        CASE 
            WHEN qs.QuestionScore > 10 AND qs.AnswerCount > 0 THEN 'PopularQuestionWithAnswers'
            WHEN qs.QuestionScore > 10 AND qs.AnswerCount = 0 THEN 'PopularUnanswered'
            WHEN qs.QuestionScore <= 10 AND qs.AnswerCount > 0 THEN 'LowScoreAnswered'
            ELSE 'LowScoreUnanswered'
        END as QuestionAnswerStatus,
        DENSE_RANK() OVER (PARTITION BY qs.OwnerUserId ORDER BY qs.Score DESC) as QuestionRankInUser,
        CASE 
            WHEN qs.AnswerCount > (SELECT AVG(AnswerCount) FROM Posts WHERE PostTypeId = 1) THEN 'AboveAvgAnswers'
            WHEN qs.AnswerCount < (SELECT AVG(AnswerCount) FROM Posts WHERE PostTypeId = 1) THEN 'BelowAvgAnswers'
            ELSE 'AvgAnswers'
        END as AnswerVolume,
        ROW_NUMBER() OVER (ORDER BY qs.Score DESC, qs.AnswerCount DESC) as OverallQuestionRank
    FROM TopUsers tu
    LEFT JOIN QuestionStats qs ON tu.UserId = qs.OwnerUserId
    LEFT JOIN AnswerStats asa ON qs.QuestionId = asa.QuestionId
    WHERE qs.QuestionId IS NOT NULL
)
SELECT 
    ca.UserId,
    ca.DisplayName,
    ca.Reputation,
    ca.TotalPosts,
    ca.Questions,
    ca.Answers,
    ca.Wikis,
    ca.TotalScore,
    ca.Badges,
    ca.AvgPostScore,
    ca.ReputationPercentile,
    ca.PerformanceQuartile,
    ca.QuestionId,
    ca.Title,
    ca.QuestionScore,
    ca.ViewCount,
    ca.AnswerCount,
    ca.CommentCount,
    ca.HasAcceptedAnswer,
    ca.DaysOpen,
    ca.FavoriteCount,
    ca.QuestionTags,
    ca.ScoreCategory,
    ca.AnswerStatus,
    ca.VoteCount,
    ca.CommentCountOnQuestion,
    ca.AnswerId,
    ca.AnswerScore,
    ca.AnswerViewCount,
    ca.RankingInQuestion,
    ca.ScorePercentileInQuestion,
    ca.AgeCategory,
    ca.PreviousAnswerScore,
    ca.AnswerScoreVsQuestion,
    ca.AnswerType,
    ca.QuestionEngagementStatus,
    ca.AnswerScorePercentage,
    ca.QuestionAnswerStatus,
    ca.QuestionRankInUser,
    ca.AnswerVolume,
    ca.OverallQuestionRank,
    CASE 
        WHEN ca.AnswerScore < 0 THEN 'NegativeScore'
        WHEN ca.AnswerScore BETWEEN 0 AND 5 THEN 'LowScore'
        WHEN ca.AnswerScore BETWEEN 6 AND 15 THEN 'MediumScore'
        WHEN ca.AnswerScore BETWEEN 16 AND 50 THEN 'HighScore'
        ELSE 'VeryHighScore'
    END as AnswerScoringTier,
    CASE 
        WHEN ca.QuestionScore > 100 THEN 'VeryPopular'
        WHEN ca.QuestionScore > 50 THEN 'Popular'
        WHEN ca.QuestionScore > 25 THEN 'ModeratelyPopular'
        WHEN ca.QuestionScore > 0 THEN 'LowPopular'
        ELSE 'NoPopularity'
    END as QuestionPopularity,
    CASE 
        WHEN ca.HasAcceptedAnswer = 'Yes' AND ca.AnswerScore > 0 THEN 'AnsweredWithScore'
        WHEN ca.HasAcceptedAnswer = 'Yes' AND ca.AnswerScore <= 0 THEN 'AnsweredWithoutScore'
        WHEN ca.HasAcceptedAnswer = 'No' AND ca.AnswerScore > 0 THEN 'UnansweredWithScore'
        ELSE 'UnansweredWithoutScore'
    END as StatusCombination,
    NULLIF(
        (CAST(ca.QuestionScore as FLOAT) / NULLIF(ca.AnswerCount, 0)), 
        0
    ) as ScorePerAnswer,
    DATEDIFF(day, '1900-01-01', ca.CreationDate) as DaysSinceEpoch,
    ABS(ca.QuestionScore - ca.AnswerScore) as ScoreDifference,
    CONCAT(
        ca.QuestionTags, 
        ' | ', 
        STRING_AGG(DISTINCT SUBSTRING(ca.QuestionTags, 1, 10), ', ') 
        OVER (PARTITION BY ca.UserId ORDER BY ca.QuestionScore DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
    ) as TagAnalysis,
    CASE 
        WHEN EXISTS(
            SELECT 1 FROM Posts p WHERE p.OwnerUserId = ca.UserId AND p.PostTypeId = 1 AND p.Score > 100
        ) THEN 'HasHighScoreQuestions'
        ELSE 'NoHighScoreQuestions'
    END as HighScoreQuestionIndicator,
    CASE 
        WHEN EXISTS(
            SELECT 1 FROM Posts p WHERE p.OwnerUserId = ca.UserId AND p.PostTypeId = 2 AND p.Score > 50
        ) THEN 'HasHighScoreAnswers'
        ELSE 'NoHighScoreAnswers'
    END as HighScoreAnswerIndicator,
    CASE 
        WHEN ca.QuestionScore >= 0 AND ca.AnswerScore >= 0 THEN 'NonNegativeScores'
        ELSE 'MixedScores'
    END as ScoreNature
FROM ComplexAnalysis ca
WHERE ca.QuestionId IS NOT NULL
    AND (
        ca.QuestionScore >= (
            SELECT PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY Score) 
            FROM Posts 
            WHERE PostTypeId = 1
        )
        OR ca.AnswerScore >= (
            SELECT PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY Score) 
            FROM Posts 
            WHERE PostTypeId = 2
        )
    )
ORDER BY 
    ca.TotalScore DESC,
    ca.QuestionScore DESC,
    ca.AnswerScore DESC,
    ca.Reputation DESC
LIMIT 1000;
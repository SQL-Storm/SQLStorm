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
        (TIMESTAMP '2024-10-01 12:34:56' - u.CreationDate) as AccountAgeInterval,
        EXTRACT(epoch FROM (TIMESTAMP '2024-10-01 12:34:56' - u.CreationDate))/86400 AS AccountAgeDays,
        CASE 
            WHEN u.Reputation > 10000 THEN 'Elite'
            WHEN u.Reputation > 5000 THEN 'Veteran'
            WHEN u.Reputation > 1000 THEN 'Active'
            ELSE 'Newbie'
        END as ReputationTier,
        STRING_AGG(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Title END, ', ') as QuestionTitles,
        SUM(COALESCE(p.Score, 0)) as TotalScore,
        AVG(COALESCE(p.Score, 0)) as AvgScore,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.ViewCount > 1000 THEN p.Id END) as HighViewQuestions
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.CreationDate
),
RankedUsers AS (
    SELECT 
        uas.*,
        ROW_NUMBER() OVER (ORDER BY TotalScore DESC) as ScoreRank,
        RANK() OVER (ORDER BY Reputation DESC) as ReputationRank,
        DENSE_RANK() OVER (ORDER BY Questions DESC) as QuestionRank,
        NTILE(10) OVER (ORDER BY TotalPosts DESC) as PostTenile
    FROM UserActivityStats uas
),
PostAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        COALESCE((SELECT COUNT(*) FROM Posts WHERE ParentId = p.Id AND PostTypeId = 2), 0) as AnswerCountAdjusted,
        EXTRACT(epoch FROM (TIMESTAMP '2024-10-01 12:34:56' - p.CreationDate))/86400 AS PostAgeDays,
        CASE 
            WHEN p.ViewCount > 1000 THEN 'Popular'
            WHEN p.ViewCount > 100 THEN 'Moderate'
            ELSE 'Low'
        END as PopularityTier,
        CAST(p.Score AS DOUBLE PRECISION) / NULLIF(p.ViewCount, 0) as ScoreToViewRatio,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as UserPostSequence,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PrevScore,
        LEAD(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as NextScore
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserPostStats AS (
    SELECT 
        r.UserId,
        r.DisplayName,
        r.Reputation,
        r.TotalPosts,
        r.Questions,
        r.Answers,
        r.Comments,
        r.Badges,
        r.ScoreRank,
        r.ReputationRank,
        r.QuestionRank,
        r.PostTenile,
        r.ReputationTier,
        COUNT(pa.PostId) as AnalyzedPosts,
        SUM(CASE WHEN pa.PostTypeId = 1 THEN 1 ELSE 0 END) as AnalyzedQuestions,
        SUM(CASE WHEN pa.PostTypeId = 2 THEN 1 ELSE 0 END) as AnalyzedAnswers,
        AVG(pa.Score) as AvgPostScore,
        MAX(pa.ViewCount) as MaxViews,
        MIN(pa.ViewCount) as MinViews,
        SUM(pa.ScoreToViewRatio) as TotalScoreViewRatio
    FROM RankedUsers r
    LEFT JOIN PostAnalysis pa ON r.UserId = pa.OwnerUserId
    WHERE r.TotalPosts > 0
    GROUP BY 
        r.UserId, r.DisplayName, r.Reputation, r.TotalPosts, r.Questions, r.Answers, 
        r.Comments, r.Badges, r.ScoreRank, r.ReputationRank, r.QuestionRank, r.PostTenile, r.ReputationTier
),
FinalAnalysis AS (
    SELECT 
        ups.UserId,
        ups.DisplayName,
        ups.Reputation,
        ups.TotalPosts,
        ups.Questions,
        ups.Answers,
        ups.Comments,
        ups.Badges,
        ups.ScoreRank,
        ups.ReputationRank,
        ups.QuestionRank,
        ups.PostTenile,
        ups.ReputationTier,
        ups.AnalyzedPosts,
        ups.AnalyzedQuestions,
        ups.AnalyzedAnswers,
        ups.AvgPostScore,
        ups.MaxViews,
        ups.MinViews,
        ups.TotalScoreViewRatio,
        CASE 
            WHEN ups.AnalyzedPosts > 0 THEN 
                CAST(ups.AnalyzedQuestions AS DOUBLE PRECISION) / NULLIF(ups.AnalyzedPosts, 0) 
            ELSE 0 
        END as QuestionRatio,
        CASE 
            WHEN ups.AnalyzedPosts > 0 THEN 
                CAST(ups.AnalyzedAnswers AS DOUBLE PRECISION) / NULLIF(ups.AnalyzedPosts, 0) 
            ELSE 0 
        END as AnswerRatio,
        CASE 
            WHEN ups.AnalyzedAnswers > 0 THEN 
                CAST(ups.AnalyzedQuestions AS DOUBLE PRECISION) / NULLIF(ups.AnalyzedAnswers, 0) 
            ELSE 0 
        END as QtoARatio,
        COALESCE(
            (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = ups.UserId AND PostTypeId = 1 AND Score >= 10), 
            0
        ) as HighScoreQuestions,
        COALESCE(
            (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = ups.UserId AND PostTypeId = 2 AND Score >= 5), 
            0
        ) as HighScoreAnswers,
        (SELECT COUNT(*) FROM Votes WHERE UserId = ups.UserId AND VoteTypeId = 2) as UpVotesReceived,
        (SELECT COUNT(*) FROM Votes WHERE UserId = ups.UserId AND VoteTypeId = 3) as DownVotesReceived,
        CASE 
            WHEN ups.AnalyzedPosts > 0 AND ups.ScoreRank <= 10 THEN 'Top Scorer'
            WHEN ups.AnalyzedPosts > 0 AND ups.ReputationRank <= 10 THEN 'Top Reputable'
            ELSE 'Regular User'
        END as UserCategory
    FROM UserPostStats ups
)
SELECT 
    f.UserId,
    f.DisplayName,
    f.Reputation,
    f.TotalPosts,
    f.Questions,
    f.Answers,
    f.Comments,
    f.Badges,
    f.ScoreRank,
    f.ReputationRank,
    f.QuestionRank,
    f.PostTenile,
    f.ReputationTier,
    f.AnalyzedPosts,
    f.AnalyzedQuestions,
    f.AnalyzedAnswers,
    f.AvgPostScore,
    f.MaxViews,
    f.MinViews,
    f.TotalScoreViewRatio,
    f.QuestionRatio,
    f.AnswerRatio,
    f.QtoARatio,
    f.HighScoreQuestions,
    f.HighScoreAnswers,
    f.UpVotesReceived,
    f.DownVotesReceived,
    f.UserCategory,
    CASE 
        WHEN f.TotalScoreViewRatio > 10 AND f.HighScoreQuestions > 5 THEN 'High Impact'
        WHEN f.TotalScoreViewRatio > 5 AND f.HighScoreAnswers > 10 THEN 'Active Contributor'
        WHEN f.TotalScoreViewRatio > 1 AND f.AnalyzedPosts > 50 THEN 'Consistent Author'
        ELSE 'Regular Participant'
    END as ContributionLevel,
    ABS(
        COALESCE((SELECT MAX(p.Score) FROM Posts p WHERE p.OwnerUserId = f.UserId AND p.PostTypeId = 1), 0) - 
        COALESCE((SELECT MIN(p.Score) FROM Posts p WHERE p.OwnerUserId = f.UserId AND p.PostTypeId = 1), 0)
    ) as ScoreRange,
    STRING_AGG(
        CASE 
            WHEN f.AnalyzedQuestions > 0 THEN CAST(f.AnalyzedQuestions as VARCHAR) || 'Q'
            WHEN f.AnalyzedAnswers > 0 THEN CAST(f.AnalyzedAnswers as VARCHAR) || 'A'
            ELSE '0'
        END, 
        '; '
    ) as PostTypeCounts,
    CASE 
        WHEN SUM(f.AnalyzedQuestions) OVER (ORDER BY f.ScoreRank) > (SELECT SUM(AnalyzedQuestions) FROM FinalAnalysis) * 0.8 THEN 'Top 20%'
        WHEN SUM(f.AnalyzedQuestions) OVER (ORDER BY f.ScoreRank) > (SELECT SUM(AnalyzedQuestions) FROM FinalAnalysis) * 0.5 THEN 'Top 50%'
        ELSE 'Below 50%'
    END as PerformanceQuartile
FROM FinalAnalysis f
GROUP BY 
    f.UserId, f.DisplayName, f.Reputation, f.TotalPosts, f.Questions, f.Answers, f.Comments, f.Badges,
    f.ScoreRank, f.ReputationRank, f.QuestionRank, f.PostTenile, f.ReputationTier,
    f.AnalyzedPosts, f.AnalyzedQuestions, f.AnalyzedAnswers, f.AvgPostScore, f.MaxViews, f.MinViews,
    f.TotalScoreViewRatio, f.QuestionRatio, f.AnswerRatio, f.QtoARatio, f.HighScoreQuestions,
    f.HighScoreAnswers, f.UpVotesReceived, f.DownVotesReceived, f.UserCategory
HAVING 
    f.TotalPosts > 0 
    AND (
        f.Questions > 1 
        OR f.Answers > 5 
        OR f.Comments > 10 
        OR f.Badges > 2
    )
ORDER BY f.ScoreRank ASC, f.Reputation DESC
LIMIT 200 OFFSET 0;
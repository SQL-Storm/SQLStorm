-- {"query": "7175.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2921} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.CreationDate,
        u.DisplayName,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        COUNT(DISTINCT c.Id) as Comments,
        COUNT(DISTINCT b.Id) as Badges,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        COALESCE(MAX(p.CreationDate), u.CreationDate) as LastActivity,
        DATEDIFF(CURRENT_TIMESTAMP, u.CreationDate) as AccountAgeDays,
        CASE 
            WHEN COUNT(DISTINCT p.Id) = 0 THEN 'Inactive'
            WHEN COUNT(DISTINCT p.Id) > 100 THEN 'Active'
            WHEN COUNT(DISTINCT p.Id) > 50 THEN 'High'
            WHEN COUNT(DISTINCT p.Id) > 10 THEN 'Medium'
            ELSE 'Low'
        END as ActivityLevel,
        AVG(COALESCE(p.Score, 0)) as AvgPostScore,
        MAX(p.ViewCount) as MaxViewCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN p.Id END) as QuestionWithAnswers,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.ParentId IS NOT NULL THEN p.Id END) as AnsweredQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN p.Id END) as ClosedQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.Score > 0 THEN p.Id END) as PositiveScoreAnswers
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.Reputation, u.CreationDate, u.DisplayName
),
RankedUsers AS (
    SELECT 
        *,
        ROW_NUMBER() OVER(ORDER BY TotalScore DESC, Reputation DESC) as ScoreRank,
        RANK() OVER(ORDER BY AccountAgeDays ASC) as SeniorityRank,
        DENSE_RANK() OVER(ORDER BY ActivityLevel DESC) as ActivityRank,
        NTILE(10) OVER(ORDER BY TotalScore DESC) as ScorePercentile
    FROM UserActivityStats
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        COALESCE(p.ViewCount, 0) as ExcerptViews,
        COALESCE(p.Score, 0) as ExcerptScore,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 500 THEN 'Moderate'
            WHEN t.Count > 100 THEN 'Niche'
            ELSE 'Obscure'
        END as TagPopularity,
        ROW_NUMBER() OVER(ORDER BY t.Count DESC) as PopularityRank
    FROM Tags t
    LEFT JOIN Posts p ON t.ExcerptPostId = p.Id
),
PostDetail AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Body,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.ParentId,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        COALESCE(p.Tags, '') as Tags,
        CASE WHEN p.ParentId IS NOT NULL THEN 'Answer' ELSE 'Question' END as PostCategory,
        DATEDIFF(CURRENT_TIMESTAMP, p.CreationDate) as AgeDays,
        p.Score * CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0.5 END as AdjustedScore,
        CASE 
            WHEN p.Score >= 100 THEN 'Gold'
            WHEN p.Score >= 50 THEN 'Silver'
            WHEN p.Score >= 10 THEN 'Bronze'
            ELSE 'Common'
        END as ScoreTier,
        CASE 
            WHEN p.ViewCount > 1000 THEN 'Viral'
            WHEN p.ViewCount > 500 THEN 'Popular'
            WHEN p.ViewCount > 100 THEN 'Noticeable'
            ELSE 'Quiet'
        END as PopularityLevel
    FROM Posts p
),
ComplexPostAnalysis AS (
    SELECT 
        pd.PostId,
        pd.Title,
        pd.Score,
        pd.ViewCount,
        pd.AgeDays,
        pd.PostCategory,
        pd.ScoreTier,
        pd.PopularityLevel,
        pd.Tags,
        pd.OwnerUserId,
        pd.AnswerCount,
        pd.CommentCount,
        pd.FavoriteCount,
        pd.AdjustedScore,
        LAG(pd.Score) OVER(PARTITION BY pd.OwnerUserId ORDER BY pd.CreationDate) as PreviousPostScore,
        LEAD(pd.Score) OVER(PARTITION BY pd.OwnerUserId ORDER BY pd.CreationDate) as NextPostScore,
        AVG(pd.Score) OVER(PARTITION BY pd.OwnerUserId) as UserAvgScore,
        COUNT(*) OVER(PARTITION BY pd.OwnerUserId) as UserPostCount,
        ROW_NUMBER() OVER(PARTITION BY pd.OwnerUserId ORDER BY pd.CreationDate) as UserPostSequence,
        RANK() OVER(ORDER BY pd.Score DESC) as GlobalScoreRank,
        PERCENT_RANK() OVER(ORDER BY pd.Score DESC) as ScorePercentileRank,
        NTH_VALUE(pd.Score, 1) OVER(PARTITION BY pd.OwnerUserId ORDER BY pd.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as UserBestScore,
        NTH_VALUE(pd.Score, 1) OVER(PARTITION BY pd.OwnerUserId ORDER BY pd.CreationDate DESC ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as UserWorstScore
    FROM PostDetail pd
    WHERE pd.PostTypeId IN (1, 2)
),
UserPostPerformance AS (
    SELECT 
        ru.UserId,
        ru.DisplayName,
        ru.Reputation,
        ru.TotalPosts,
        ru.Questions,
        ru.Answers,
        ru.Comments,
        ru.Badges,
        ru.TotalScore,
        ru.ActivityLevel,
        ru.AvgPostScore,
        ru.AccountAgeDays,
        CASE WHEN ru.TotalPosts > 0 THEN ru.TotalScore / ru.TotalPosts ELSE 0 END as AvgScorePerPost,
        CASE WHEN ru.Questions > 0 THEN ru.Answers / ru.Questions ELSE 0 END as AnswerRatio,
        CASE WHEN ru.TotalPosts > 0 THEN (ru.Badges * 100.0) / ru.TotalPosts ELSE 0 END as BadgeEfficiency,
        DENSE_RANK() OVER(ORDER BY ru.TotalScore DESC) as ScoreRank,
        CASE WHEN ru.ScoreRank <= 10 THEN 'Top 10' ELSE 'Others' END as TopPerformingGroup,
        CASE 
            WHEN ru.Reputation > 10000 THEN 'Veteran'
            WHEN ru.Reputation > 1000 THEN 'Experienced'
            WHEN ru.Reputation > 100 THEN 'Novice'
            ELSE 'Beginner'
        END as ReputationTier,
        COALESCE((SELECT MAX(pa.AdjustedScore) FROM ComplexPostAnalysis pa WHERE pa.OwnerUserId = ru.UserId), 0) as MaxPostValue,
        COALESCE((SELECT MIN(pa.AdjustedScore) FROM ComplexPostAnalysis pa WHERE pa.OwnerUserId = ru.UserId), 0) as MinPostValue,
        COALESCE((SELECT AVG(pa.Score) FROM ComplexPostAnalysis pa WHERE pa.OwnerUserId = ru.UserId), 0) as AvgPostScoreUser,
        COALESCE((SELECT COUNT(*) FROM ComplexPostAnalysis pa JOIN Posts p ON pa.PostId = p.Id WHERE p.OwnerUserId = ru.UserId AND p.Score > 0), 0) as PositiveScorePosts
    FROM RankedUsers ru
    WHERE ru.UserId IS NOT NULL
)
SELECT 
    upp.UserId,
    upp.DisplayName,
    upp.Reputation,
    upp.TotalPosts,
    upp.Questions,
    upp.Answers,
    upp.Comments,
    upp.Badges,
    upp.TotalScore,
    upp.ActivityLevel,
    upp.AvgPostScore,
    upp.AccountAgeDays,
    upp.AvgScorePerPost,
    upp.AnswerRatio,
    upp.BadgeEfficiency,
    upp.ScoreRank,
    upp.TopPerformingGroup,
    upp.ReputationTier,
    upp.MaxPostValue,
    upp.MinPostValue,
    upp.AvgPostScoreUser,
    upp.PositiveScorePosts,
    CASE 
        WHEN upp.Reputation > 10000 AND upp.TotalScore > 1000 THEN 'Elite Contributor'
        WHEN upp.Reputation > 1000 AND upp.TotalScore > 500 THEN 'High Achiever'
        WHEN upp.Reputation > 100 AND upp.TotalScore > 100 THEN 'Active Member'
        WHEN upp.Reputation > 10 AND upp.TotalScore > 10 THEN 'Contributor'
        ELSE 'Regular User'
    END as ContributionLevel,
    RANK() OVER(ORDER BY upp.Reputation DESC) as ReputationRank,
    PERCENT_RANK() OVER(ORDER BY upp.Reputation DESC) as ReputationPercentile,
    CASE 
        WHEN upp.TotalPosts > 50 AND upp.AvgPostScore > 10 THEN 'High Performer'
        WHEN upp.TotalPosts > 20 AND upp.AvgPostScore > 5 THEN 'Moderate Performer'
        WHEN upp.TotalPosts > 5 AND upp.AvgPostScore > 2 THEN 'Low Performer'
        ELSE 'Newbie'
    END as ProductivityLevel,
    COALESCE(
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = upp.UserId AND p.PostTypeId = 1 AND p.CreationDate >= DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 30 DAY)), 
        0
    ) as RecentQuestions,
    COALESCE(
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = upp.UserId AND p.PostTypeId = 2 AND p.CreationDate >= DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 30 DAY)), 
        0
    ) as RecentAnswers,
    COALESCE(
        (SELECT AVG(p.Score) FROM Posts p WHERE p.OwnerUserId = upp.UserId AND p.CreationDate >= DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 30 DAY) AND p.PostTypeId IN (1, 2)), 
        0
    ) as RecentAvgScore,
    CASE 
        WHEN upp.TotalScore > 5000 OR upp.Reputation > 5000 THEN 'Power User'
        WHEN upp.TotalScore > 1000 OR upp.Reputation > 1000 THEN 'Advanced User'
        WHEN upp.TotalScore > 100 OR upp.Reputation > 100 THEN 'Regular User'
        ELSE 'New User'
    END as UserClassification,
    (SELECT COUNT(*) FROM ComplexPostAnalysis cpa WHERE cpa.OwnerUserId = upp.UserId AND cpa.ScoreTier = 'Gold') as GoldTierPosts,
    (SELECT COUNT(*) FROM ComplexPostAnalysis cpa WHERE cpa.OwnerUserId = upp.UserId AND cpa.PopularityLevel = 'Viral') as ViralPosts,
    (SELECT COUNT(*) FROM ComplexPostAnalysis cpa WHERE cpa.OwnerUserId = upp.UserId AND cpa.GlobalScoreRank <= 100) as Top100RankPosts,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = upp.UserId AND c.CreationDate >= DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 30 DAY)) as RecentComments,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = upp.UserId AND b.Date >= DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 30 DAY)) as RecentBadges,
    DATEDIFF(CURRENT_TIMESTAMP, (SELECT MAX(p.CreationDate) FROM Posts p WHERE p.OwnerUserId = upp.UserId)) as DaysSinceLastPost,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = upp.UserId AND p.ParentId IS NOT NULL AND p.Score > 0) as AnsweredQuestionsWithScore,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = upp.UserId AND p.PostTypeId = 1 AND p.AnswerCount > 0 AND p.Score > 0) as QuestionWithAnswersScored,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = upp.UserId AND p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL) as QuestionsWithAcceptedAnswers,
    (SELECT COUNT(*) FROM Votes v JOIN Posts p ON v.PostId = p.Id WHERE p.OwnerUserId = upp.UserId AND v.VoteTypeId = 2 AND v.CreationDate >= DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 30 DAY)) as RecentUpvotesReceived,
    (SELECT COUNT(*) FROM Votes v JOIN Posts p ON v.PostId = p.Id WHERE p.OwnerUserId = upp.UserId AND v.VoteTypeId = 3 AND v.CreationDate >= DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 30 DAY)) as RecentDownvotesReceived
FROM UserPostPerformance upp
WHERE upp.UserId IS NOT NULL
AND (upp.TotalPosts > 0 OR upp.Badges > 0)
AND upp.DisplayName IS NOT NULL
ORDER BY upp.TotalScore DESC
LIMIT 10000;
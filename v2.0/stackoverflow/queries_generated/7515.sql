-- {"query": "7515.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2434} 
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
        COALESCE(SUM(p.Score), 0) as TotalScore,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        MAX(b.Date) as LastBadgeDate,
        DATEDIFF('day', u.CreationDate, CURRENT_TIMESTAMP) as AccountAgeDays,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 0 THEN 
                (COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) * 100.0 / COUNT(DISTINCT p.Id))
            ELSE 0 
        END as QuestionPercentage,
        CASE 
            WHEN u.Reputation > 10000 THEN 'Elite'
            WHEN u.Reputation > 1000 THEN 'Advanced'
            WHEN u.Reputation > 100 THEN 'Intermediate'
            ELSE 'Beginner'
        END as ReputationLevel
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.CreationDate
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        TotalPosts,
        Questions,
        Answers,
        Comments,
        Badges,
        TotalScore,
        AccountAgeDays,
        QuestionPercentage,
        ReputationLevel,
        RANK() OVER (ORDER BY TotalScore DESC) as ScoreRank,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC) as ReputationRank
    FROM UserActivityStats
    WHERE TotalPosts > 0
),
PostComplexity AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Body,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostType,
        CASE 
            WHEN p.Tags IS NOT NULL AND LENGTH(p.Tags) > 0 THEN 
                ARRAY_LENGTH(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><'), 1)
            ELSE 0
        END as TagCount,
        COALESCE(p.AnswerCount, 0) as AnswerCountCoalesced,
        COALESCE(p.CommentCount, 0) as CommentCountCoalesced,
        COALESCE(p.FavoriteCount, 0) as FavoriteCountCoalesced,
        CASE 
            WHEN p.Score > 10 THEN 'High'
            WHEN p.Score > 5 THEN 'Medium'
            WHEN p.Score > 0 THEN 'Low'
            ELSE 'Very Low'
        END as ScoreLevel,
        DATEDIFF('day', p.CreationDate, CURRENT_TIMESTAMP) as AgeInDays,
        CASE 
            WHEN COALESCE(p.ViewCount, 0) > 1000 THEN 'Popular'
            WHEN COALESCE(p.ViewCount, 0) > 100 THEN 'Moderate'
            WHEN COALESCE(p.ViewCount, 0) > 0 THEN 'Low'
            ELSE 'Very Low'
        END as PopularityLevel
    FROM Posts p
    WHERE p.Id IS NOT NULL
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
        tu.TotalScore,
        tu.AccountAgeDays,
        tu.QuestionPercentage,
        tu.ReputationLevel,
        tu.ScoreRank,
        tu.ReputationRank,
        pc.PostId,
        pc.Title,
        pc.Score as PostScore,
        pc.ViewCount,
        pc.AnswerCountCoalesced,
        pc.CommentCountCoalesced,
        pc.FavoriteCountCoalesced,
        pc.PostType,
        pc.TagCount,
        pc.ScoreLevel,
        pc.AgeInDays,
        pc.PopularityLevel,
        CASE 
            WHEN (pc.AnswerCountCoalesced * 1.0) / NULLIF(pc.CommentCountCoalesced, 0) > 2 
            THEN 'High Answer-to-Comment Ratio'
            WHEN (pc.AnswerCountCoalesced * 1.0) / NULLIF(pc.CommentCountCoalesced, 0) < 0.5 
            THEN 'Low Answer-to-Comment Ratio'
            ELSE 'Normal Answer-to-Comment Ratio'
        END as AnswerCommentRatio,
        ROW_NUMBER() OVER (PARTITION BY tu.UserId ORDER BY pc.Score DESC) as UserPostRank,
        DENSE_RANK() OVER (ORDER BY pc.Score DESC) as GlobalPostRank,
        NTILE(10) OVER (ORDER BY pc.Score DESC) as ScoreDecile,
        AVG(pc.Score) OVER (PARTITION BY tu.UserId) as AvgUserPostScore,
        MAX(pc.Score) OVER (PARTITION BY tu.UserId) as MaxUserPostScore,
        MIN(pc.Score) OVER (PARTITION BY tu.UserId) as MinUserPostScore,
        PERCENT_RANK() OVER (ORDER BY pc.Score) as ScorePercentile
    FROM TopUsers tu
    INNER JOIN PostComplexity pc ON tu.UserId = pc.Id
    WHERE pc.Score IS NOT NULL
),
UserEngagementSummary AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        TotalPosts,
        Questions,
        Answers,
        Comments,
        Badges,
        TotalScore,
        AccountAgeDays,
        QuestionPercentage,
        ReputationLevel,
        ScoreRank,
        ReputationRank,
        COUNT(PostId) as UserPostCount,
        SUM(PostScore) as SumUserPostScore,
        AVG(PostScore) as AvgUserPostScore,
        MAX(PostScore) as MaxUserPostScore,
        MIN(PostScore) as MinUserPostScore,
        ROUND(AVG(TagCount), 2) as AvgTagCount,
        MAX(AgeInDays) as MaxPostAge,
        SUM(AnswerCountCoalesced) as TotalAnswers,
        SUM(CommentCountCoalesced) as TotalComments,
        SUM(FavoriteCountCoalesced) as TotalFavorites,
        STRING_AGG(DISTINCT PostType, ', ') as PostTypes,
        STRING_AGG(DISTINCT ScoreLevel, ', ') as ScoreLevels,
        STRING_AGG(DISTINCT PopularityLevel, ', ') as PopularityLevels,
        STRING_AGG(DISTINCT AnswerCommentRatio, ', ') as AnswerCommentRatios
    FROM CombinedAnalysis
    GROUP BY 
        UserId, DisplayName, Reputation, TotalPosts, Questions, Answers, Comments, Badges, 
        TotalScore, AccountAgeDays, QuestionPercentage, ReputationLevel, ScoreRank, ReputationRank
)
SELECT 
    ues.UserId,
    ues.DisplayName,
    ues.Reputation,
    ues.TotalPosts,
    ues.Questions,
    ues.Answers,
    ues.Comments,
    ues.Badges,
    ues.TotalScore,
    ues.AccountAgeDays,
    ues.QuestionPercentage,
    ues.ReputationLevel,
    ues.ScoreRank,
    ues.ReputationRank,
    ues.UserPostCount,
    ues.SumUserPostScore,
    ues.AvgUserPostScore,
    ues.MaxUserPostScore,
    ues.MinUserPostScore,
    ues.AvgTagCount,
    ues.MaxPostAge,
    ues.TotalAnswers,
    ues.TotalComments,
    ues.TotalFavorites,
    ues.PostTypes,
    ues.ScoreLevels,
    ues.PopularityLevels,
    ues.AnswerCommentRatios,
    CASE 
        WHEN ues.Reputation > 10000 AND ues.UserPostCount > 100 THEN 'High Engagement Elite'
        WHEN ues.Reputation > 1000 AND ues.UserPostCount > 50 THEN 'High Engagement Advanced'
        WHEN ues.Reputation > 100 AND ues.UserPostCount > 25 THEN 'High Engagement Intermediate'
        ELSE 'Regular User'
    END as EngagementLevel,
    CASE 
        WHEN ues.AccountAgeDays > 365 AND ues.TotalPosts > 50 THEN 'Long Term Contributor'
        WHEN ues.AccountAgeDays > 180 AND ues.TotalPosts > 25 THEN 'Active Contributor'
        WHEN ues.AccountAgeDays > 30 AND ues.TotalPosts > 10 THEN 'New Contributor'
        ELSE 'Newbie'
    END as ContributionLevel,
    CASE 
        WHEN ues.AvgUserPostScore > 100 THEN 'Top Performer'
        WHEN ues.AvgUserPostScore > 50 THEN 'High Performer'
        WHEN ues.AvgUserPostScore > 25 THEN 'Medium Performer'
        ELSE 'Low Performer'
    END as PerformanceLevel,
    CONCAT(ues.DisplayName, ' - ', ues.ReputationLevel, ' - ', ues.ContributionLevel, ' - ', ues.PerformanceLevel) as UserProfile,
    ROW_NUMBER() OVER (ORDER BY ues.TotalScore DESC, ues.Reputation DESC) as OverallRank,
    RANK() OVER (PARTITION BY ues.ReputationLevel ORDER BY ues.TotalScore DESC) as ReputationGroupRank,
    COUNT(*) OVER () as TotalUsers,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ues.TotalScore) as MedianScore,
    AVG(ues.TotalScore) OVER () as AvgScore,
    STDEV(ues.TotalScore) OVER () as StdDevScore,
    (ues.TotalScore - AVG(ues.TotalScore) OVER ()) / NULLIF(STDEV(ues.TotalScore) OVER (), 0) as ZScore,
    CASE 
        WHEN ues.MaxUserPostScore > 500 THEN 'Consistent High Performer'
        WHEN ues.MaxUserPostScore > 100 THEN 'Occasional High Performer'
        ELSE 'Regular Performer'
    END as ConsistencyLevel,
    COALESCE(ues.Answers, 0) + COALESCE(ues.Comments, 0) + COALESCE(ues.Badges, 0) as EngagementMultiplier,
    CASE 
        WHEN ues.Reputation > 5000 AND ues.AccountAgeDays > 365 THEN 
            (ues.Reputation * ues.UserPostCount * 1.0) / NULLIF(ues.AccountAgeDays, 0)
        ELSE 0 
    END as ReputationEfficiency
FROM UserEngagementSummary ues
WHERE ues.UserId IS NOT NULL
    AND ues.TotalPosts > 0
ORDER BY ues.TotalScore DESC, ues.Reputation DESC
LIMIT 1000;
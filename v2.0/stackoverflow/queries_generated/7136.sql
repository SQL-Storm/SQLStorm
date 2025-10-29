-- {"query": "7136.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2430} 
WITH UserActivityStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
        COUNT(DISTINCT c.Id) AS Comments,
        COUNT(DISTINCT b.Id) AS Badges,
        MAX(p.CreationDate) AS LastPostDate,
        AVG(p.Score) AS AvgPostScore,
        SUM(p.ViewCount) AS TotalViews,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') WITHIN GROUP (ORDER BY p.Tags) AS AllTagsUsed
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation
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
        LastPostDate,
        AvgPostScore,
        TotalViews,
        AllTagsUsed,
        ROW_NUMBER() OVER (ORDER BY TotalPosts DESC, Reputation DESC) AS Ranking,
        NTILE(10) OVER (ORDER BY Reputation DESC) AS ReputationDecile,
        CASE 
            WHEN TotalPosts > 100 AND AvgPostScore > 5 THEN 'Highly Active'
            WHEN TotalPosts > 50 AND AvgPostScore > 2 THEN 'Active'
            WHEN TotalPosts > 10 AND AvgPostScore > 0 THEN 'Regular'
            ELSE 'Casual'
        END AS ActivityLevel
    FROM UserActivityStats
),
PostComplexity AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        CASE 
            WHEN p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2 THEN 
                ARRAY_LENGTH(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><'), 1)
            ELSE 0 
        END AS TagCount,
        CASE 
            WHEN p.Body IS NOT NULL AND LENGTH(p.Body) > 1000 THEN 'Long'
            WHEN p.Body IS NOT NULL AND LENGTH(p.Body) > 500 THEN 'Medium' 
            WHEN p.Body IS NOT NULL THEN 'Short'
            ELSE 'Empty'
        END AS BodyLengthCategory,
        DATEDIFF(day, p.CreationDate, CURRENT_TIMESTAMP) AS DaysOld,
        COALESCE(p.AcceptedAnswerId, 0) AS HasAcceptedAnswer,
        COALESCE(p.ClosedDate, p.CommunityOwnedDate) AS ClosedOrCommunityOwnedDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PostRankByUser,
        LAG(p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostDate,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostScore,
        CASE 
            WHEN p.OwnerUserId IS NOT NULL THEN 
                DATEDIFF(day, LAG(p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate), p.CreationDate)
            ELSE NULL 
        END AS DaysBetweenPosts
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) 
),
UserPostAnalysis AS (
    SELECT 
        tu.UserId,
        tu.DisplayName,
        tu.Reputation,
        tu.TotalPosts,
        tu.Questions,
        tu.Answers,
        tu.Comments,
        tu.Badges,
        tu.LastPostDate,
        tu.AvgPostScore,
        tu.TotalViews,
        tu.AllTagsUsed,
        tu.Ranking,
        tu.ReputationDecile,
        tu.ActivityLevel,
        AVG(pc.Score) AS AvgPostScorePerUser,
        MAX(pc.Score) AS MaxPostScorePerUser,
        MIN(pc.ViewCount) AS MinViewCountPerUser,
        SUM(CASE WHEN pc.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN pc.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(pc.BodyLengthCategory = 'Long') AS AvgPercentageOfLongPosts,
        SUM(CASE WHEN pc.TagCount > 5 THEN 1 ELSE 0 END) AS HighTagCountPosts,
        COUNT(CASE WHEN pc.DaysBetweenPosts > 30 THEN 1 END) AS PostsWithLongGaps,
        STRING_AGG(DISTINCT CASE WHEN pc.TagCount > 3 THEN pc.Title END, '; ') AS HighTagQuestionTitles
    FROM TopUsers tu
    LEFT JOIN PostComplexity pc ON tu.UserId = pc.OwnerUserId
    GROUP BY tu.UserId, tu.DisplayName, tu.Reputation, tu.TotalPosts, 
             tu.Questions, tu.Answers, tu.Comments, tu.Badges, 
             tu.LastPostDate, tu.AvgPostScore, tu.TotalViews, 
             tu.AllTagsUsed, tu.Ranking, tu.ReputationDecile, tu.ActivityLevel
),
EngagementMetrics AS (
    SELECT 
        upa.UserId,
        upa.DisplayName,
        upa.Reputation,
        upa.TotalPosts,
        upa.ActivityLevel,
        upa.QuestionCount,
        upa.AnswerCount,
        upa.AvgPostScorePerUser,
        upa.MaxPostScorePerUser,
        upa.MinViewCountPerUser,
        upa.AvgPercentageOfLongPosts,
        upa.HighTagCountPosts,
        COALESCE(upa.PostsWithLongGaps, 0) AS PostsWithLongGaps,
        CASE 
            WHEN upa.PostsPerUser > 0 THEN CAST(upa.AnswerCount AS FLOAT) / upa.PostsPerUser
            ELSE 0 
        END AS AnswerRatio,
        upa.HighTagQuestionTitles,
        CASE 
            WHEN upa.Reputation > 10000 AND upa.QuestionCount > 10 THEN 'Elite'
            WHEN upa.Reputation > 5000 AND upa.QuestionCount > 5 THEN 'Advanced'
            WHEN upa.Reputation > 1000 AND upa.QuestionCount > 1 THEN 'Intermediate'
            ELSE 'Beginner'
        END AS UserCategory,
        CASE 
            WHEN upa.Reputation > 1000 AND upa.QuestionCount > 5 AND upa.MaxPostScorePerUser > 10 THEN 'Highly Engaged'
            WHEN upa.Reputation > 500 AND upa.QuestionCount > 2 THEN 'Moderate'
            ELSE 'Low'
        END AS EngagementLevel
    FROM UserPostAnalysis upa
),
ComplexPostAnalysis AS (
    SELECT 
        pc.PostId,
        pc.Title,
        pc.Score,
        pc.ViewCount,
        pc.AnswerCount,
        pc.CommentCount,
        pc.FavoriteCount,
        pc.CreationDate,
        pc.OwnerUserId,
        pc.PostTypeId,
        pc.TagCount,
        pc.BodyLengthCategory,
        pc.DaysOld,
        pc.HasAcceptedAnswer,
        pc.ClosedOrCommunityOwnedDate,
        pc.PostRankByUser,
        pc.PreviousPostDate,
        pc.PreviousPostScore,
        pc.DaysBetweenPosts,
        LAG(pc.ViewCount) OVER (ORDER BY pc.CreationDate) AS PrevViewCount,
        AVG(pc.Score) OVER (ORDER BY pc.CreationDate ROWS BETWEEN 3 PRECEDING AND CURRENT ROW) AS MovingAvgScore3Posts,
        AVG(pc.ViewCount) OVER (ORDER BY pc.CreationDate ROWS BETWEEN 5 PRECEDING AND CURRENT ROW) AS MovingAvgViews5Posts,
        DENSE_RANK() OVER (ORDER BY pc.Score DESC) AS ScoreRank,
        PERCENT_RANK() OVER (ORDER BY pc.ViewCount DESC) AS ViewPercentile,
        CASE 
            WHEN pc.Score > 50 AND pc.ViewCount > 1000 THEN 'Viral'
            WHEN pc.Score > 20 AND pc.ViewCount > 500 THEN 'Popular'
            WHEN pc.Score > 5 AND pc.ViewCount > 100 THEN 'Noticeable'
            ELSE 'Standard'
        END AS PopularityCategory,
        CASE 
            WHEN pc.TagCount > 3 AND pc.BodyLengthCategory = 'Long' THEN 'Complex'
            WHEN pc.TagCount > 0 AND pc.BodyLengthCategory = 'Medium' THEN 'Moderate'
            ELSE 'Simple'
        END AS ComplexityLevel,
        CASE 
            WHEN pc.DaysOld < 7 THEN 'New'
            WHEN pc.DaysOld < 30 THEN 'Recent'
            WHEN pc.DaysOld < 90 THEN 'Seasonal'
            ELSE 'Legacy'
        END AS AgeCategory,
        COALESCE(
            (SELECT COUNT(*) FROM Comments c WHERE c.PostId = pc.PostId AND c.Score > 5),
            0
        ) AS HighScoreCommentsCount,
        COALESCE(
            (SELECT COUNT(*) FROM Voters v WHERE v.PostId = pc.PostId AND v.VoteTypeId IN (2,3)),
            0
        ) AS VotingActivityCount
    FROM PostComplexity pc
    WHERE pc.PostTypeId IN (1, 2)
)
SELECT 
    'Performance Benchmark Report' AS ReportTitle,
    COUNT(DISTINCT e.UserId) AS ActiveUsers,
    COUNT(DISTINCT cpa.PostId) AS TotalPostsAnalyzed,
    AVG(e.Reputation) AS AvgReputation,
    AVG(e.MaxPostScorePerUser) AS AvgMaxPostScore,
    COUNT(*) AS ReportGenerationCount,
    STRING_AGG(DISTINCT e.UserCategory, ', ') AS UserCategories,
    STRING_AGG(DISTINCT cpa.PopularityCategory, ', ') AS PopularityCategories,
    STRING_AGG(DISTINCT cpa.AgeCategory, ', ') AS AgeCategories,
    STRING_AGG(DISTINCT e.ActivityLevel, ', ') AS ActivityLevels,
    COUNT(CASE WHEN e.AnswerRatio > 0.5 THEN 1 END) AS HighAnswerRatioUsers,
    COUNT(CASE WHEN cpa.TagCount > 10 THEN 1 END) AS HighTagPosts,
    COUNT(CASE WHEN cpa.Score > 100 THEN 1 END) AS HighScorePosts,
    COUNT(CASE WHEN cpa.ViewCount > 5000 THEN 1 END) AS HighViewPosts,
    COUNT(CASE WHEN e.PostsWithLongGaps > 10 THEN 1 END) AS UsersWithLongPostGaps,
    COUNT(DISTINCT CASE WHEN cpa.VotingActivityCount > 2 THEN cpa.PostId END) AS HighlyVotedPosts,
    COUNT(DISTINCT CASE WHEN cpa.HighScoreCommentsCount > 3 THEN cpa.PostId END) AS WellCommentedPosts
FROM EngagementMetrics e
FULL OUTER JOIN ComplexPostAnalysis cpa ON e.UserId IS NOT NULL AND e.UserId = cpa.OwnerUserId
WHERE e.UserId IS NOT NULL OR cpa.PostId IS NOT NULL
HAVING COUNT(*) > 0;
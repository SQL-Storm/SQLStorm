-- {"query": "7185.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2234} 
WITH UserActivitySummary AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
        COUNT(DISTINCT c.Id) AS Comments,
        COUNT(DISTINCT b.Id) AS Badges,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(c.CreationDate) AS LastCommentDate,
        MAX(b.Date) AS LastBadgeDate,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 0 AND COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0 
            THEN CAST(COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS FLOAT) / COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END)
            ELSE NULL 
        END AS AnswerToQuestionRatio,
        ROW_NUMBER() OVER (ORDER BY (COUNT(DISTINCT p.Id) + COUNT(DISTINCT c.Id) + COUNT(DISTINCT b.Id)) DESC) AS ActivityRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id > 0 AND u.AccountId IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        Views,
        UpVotes,
        DownVotes,
        TotalPosts,
        Questions,
        Answers,
        Comments,
        Badges,
        LastPostDate,
        LastCommentDate,
        LastBadgeDate,
        AnswerToQuestionRatio,
        ActivityRank,
        CASE 
            WHEN Reputation > 10000 THEN 'Premium'
            WHEN Reputation > 5000 THEN 'Advanced'
            WHEN Reputation > 1000 THEN 'Intermediate'
            ELSE 'Beginner'
        END AS ReputationTier
    FROM UserActivitySummary
    WHERE ActivityRank <= 500
),
UserPostStats AS (
    SELECT 
        p.OwnerUserId,
        COUNT(p.Id) AS PostCount,
        AVG(p.Score) AS AvgScore,
        MAX(p.Score) AS MaxScore,
        MIN(p.Score) AS MinScore,
        SUM(p.ViewCount) AS TotalViews,
        AVG(p.ViewCount) AS AvgViews,
        STRING_AGG(p.Title, ' | ' ORDER BY p.CreationDate) AS PostTitles
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY p.OwnerUserId
),
QualifiedQuestions AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.AnswerCount,
        p.CommentCount,
        p.Tags,
        CASE 
            WHEN p.AnswerCount > 0 THEN (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = p.Id AND a.PostTypeId = 2 AND a.Score > 0)
            ELSE 0 
        END AS PositiveAnswers,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCountWithReplies,
        p.Score * (1 + CASE WHEN p.AnswerCount > 10 THEN 0.2 ELSE 0 END) AS WeightedScore
    FROM Posts p
    WHERE p.PostTypeId = 1 
        AND p.ViewCount > 0
        AND p.Score >= 0
        AND p.CreationDate >= '2020-01-01'
        AND EXISTS (SELECT 1 FROM Posts a WHERE a.ParentId = p.Id AND a.PostTypeId = 2)
),
TopQuestionPosts AS (
    SELECT 
        q.QuestionId,
        q.Title,
        q.Score,
        q.ViewCount,
        q.CreationDate,
        q.OwnerUserId,
        q.AnswerCount,
        q.CommentCount,
        q.Tags,
        q.PositiveAnswers,
        q.CommentCountWithReplies,
        q.WeightedScore,
        DENSE_RANK() OVER (ORDER BY q.WeightedScore DESC) AS ScoreRank,
        NTH_VALUE(q.Title, 1) OVER (ORDER BY q.WeightedScore DESC ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS HighestScoreTitle
    FROM QualifiedQuestions q
),
AnswerAnalysis AS (
    SELECT 
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.OwnerUserId,
        a.Score,
        a.CreationDate,
        a.LastEditDate,
        RANK() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC) AS AnswerRankWithinQuestion,
        ROW_NUMBER() OVER (ORDER BY a.Score DESC) AS GlobalAnswerRank,
        AVG(a.Score) OVER (PARTITION BY a.ParentId) AS AvgScorePerQuestion,
        CASE 
            WHEN a.Score > 10 THEN 'High Value'
            WHEN a.Score > 5 THEN 'Medium Value'
            ELSE 'Low Value'
        END AS AnswerValueCategory,
        LAG(a.Score, 1) OVER (ORDER BY a.CreationDate) AS PreviousAnswerScore
    FROM Posts a
    WHERE a.PostTypeId = 2
),
TagPerformance AS (
    SELECT 
        t.TagName,
        t.Count AS TagCount,
        t.ExcerptPostId,
        CAST(t.Count AS FLOAT) / (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 1 AND Tags LIKE '%' || t.TagName || '%') AS TagDensity,
        CASE 
            WHEN t.Count > (SELECT AVG(Count) FROM Tags) THEN 'Above Average'
            WHEN t.Count > (SELECT AVG(Count) FROM Tags) * 0.5 THEN 'Average'
            ELSE 'Below Average'
        END AS TagPopularityLevel
    FROM Tags t
    WHERE t.Count > 0
),
FinalAnalysis AS (
    SELECT 
        tu.UserId,
        tu.DisplayName,
        tu.Reputation,
        tu.ReputationTier,
        tu.TotalPosts,
        tu.Questions,
        tu.Answers,
        tu.Comments,
        tu.Badges,
        tu.ActivityRank,
        ups.PostCount,
        ups.AvgScore,
        ups.MaxScore,
        ups.MinScore,
        ups.TotalViews,
        ups.AvgViews,
        ups.PostTitles,
        tqp.QuestionId,
        tqp.Title AS TopQuestionTitle,
        tqp.Score AS TopQuestionScore,
        tqp.ViewCount AS TopQuestionViews,
        tqp.AnswerCount AS TopQuestionAnswers,
        tqp.CommentCount AS TopQuestionComments,
        tqp.Tags AS TopQuestionTags,
        ta.AnswerId,
        ta.AnswerScore,
        ta.AnswerRankWithinQuestion,
        ta.GlobalAnswerRank,
        ta.AvgScorePerQuestion,
        ta.AnswerValueCategory,
        tp.TagName,
        tp.TagCount,
        tp.TagDensity,
        tp.TagPopularityLevel,
        CASE 
            WHEN tu.ActivityRank <= 10 THEN 'Top Contributor'
            WHEN tu.Reputation > 10000 THEN 'Elite Contributor'
            ELSE 'Regular Contributor'
        END AS ContributionLevel
    FROM TopUsers tu
    LEFT JOIN UserPostStats ups ON tu.UserId = ups.OwnerUserId
    LEFT JOIN TopQuestionPosts tqp ON tu.UserId = tqp.OwnerUserId
    LEFT JOIN (
        SELECT 
            a.OwnerUserId,
            a.Id AS AnswerId,
            a.Score AS AnswerScore,
            a.AnswerRankWithinQuestion,
            a.GlobalAnswerRank,
            a.AvgScorePerQuestion,
            a.AnswerValueCategory
        FROM AnswerAnalysis a
        WHERE a.GlobalAnswerRank <= 100
    ) ta ON tu.UserId = ta.OwnerUserId
    LEFT JOIN TagPerformance tp ON tp.TagPopularityLevel IN ('Above Average', 'Average')
)
SELECT 
    f.UserId,
    f.DisplayName,
    f.Reputation,
    f.ReputationTier,
    f.TotalPosts,
    f.Questions,
    f.Answers,
    f.Comments,
    f.Badges,
    f.ActivityRank,
    f.PostCount,
    f.AvgScore,
    f.MaxScore,
    f.MinScore,
    f.TotalViews,
    f.AvgViews,
    CASE 
        WHEN f.PostTitles IS NOT NULL THEN LEFT(f.PostTitles, 1000)
        ELSE 'No Posts'
    END AS PostTitles,
    f.QuestionId,
    CASE 
        WHEN f.TopQuestionTitle IS NOT NULL THEN LEFT(f.TopQuestionTitle, 200)
        ELSE 'No Top Question'
    END AS TopQuestionTitle,
    f.TopQuestionScore,
    f.TopQuestionViews,
    f.TopQuestionAnswers,
    f.TopQuestionComments,
    CASE 
        WHEN f.TopQuestionTags IS NOT NULL THEN REPLACE(REPLACE(REPLACE(f.TopQuestionTags, '<', ''), '>', ''), ' ', ',')
        ELSE 'No Tags'
    END AS TopQuestionTags,
    f.AnswerId,
    f.AnswerScore,
    f.AnswerRankWithinQuestion,
    f.GlobalAnswerRank,
    f.AvgScorePerQuestion,
    f.AnswerValueCategory,
    CASE 
        WHEN f.TagName IS NOT NULL THEN LEFT(f.TagName, 35)
        ELSE 'No Popular Tags'
    END AS PopularTagName,
    f.TagCount,
    f.TagDensity,
    f.TagPopularityLevel,
    f.ContributionLevel,
    (CASE WHEN f.Reputation > 1000 THEN 1 ELSE 0 END +
     CASE WHEN f.TotalPosts > 100 THEN 1 ELSE 0 END +
     CASE WHEN f.Answers > 0 THEN 1 ELSE 0 END +
     CASE WHEN f.Badges > 0 THEN 1 ELSE 0 END +
     CASE WHEN f.ActivityRank < 100 THEN 1 ELSE 0 END) AS EngagementScore
FROM FinalAnalysis f
WHERE f.UserId IS NOT NULL
    AND (f.TopQuestionScore > 10 OR f.AnswerScore > 5 OR f.Reputation > 5000)
    AND (f.TagPopularityLevel IS NOT NULL OR f.ContributionLevel IS NOT NULL)
ORDER BY f.Reputation DESC, f.TotalPosts DESC, f.ActivityRank ASC
LIMIT 10000;
-- {"query": "7489.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1980} 
WITH RECURSIVE QuestionHierarchy AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.OwnerUserId,
        p.CreationDate,
        0 AS Level,
        CAST(p.Id AS VARCHAR(1000)) AS Path
    FROM Posts p
    WHERE p.PostTypeId = 1 
    AND p.ParentId IS NULL
    AND p.CreationDate >= DATEADD(YEAR, -1, CURRENT_TIMESTAMP)
    
    UNION ALL
    
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.OwnerUserId,
        p.CreationDate,
        qh.Level + 1 AS Level,
        qh.Path || '->' || CAST(p.Id AS VARCHAR(100)) AS Path
    FROM Posts p
    INNER JOIN QuestionHierarchy qh ON p.ParentId = qh.QuestionId
    WHERE qh.Level < 3
),
UserActivityStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COALESCE(SUM(p.Score), 0) AS TotalScore,
        MAX(p.CreationDate) AS LastPostDate,
        DATEDIFF(DAY, u.CreationDate, CURRENT_TIMESTAMP) AS AccountAgeDays,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 0 THEN AVG(p.Score) 
            ELSE 0 
        END AS AvgQuestionScore,
        COALESCE(SUM(p.AnswerCount), 0) AS TotalAnswers
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId IN (1,2)
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= DATEADD(YEAR, -2, CURRENT_TIMESTAMP)
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.CreationDate
    HAVING COUNT(DISTINCT p.Id) > 0 OR COUNT(DISTINCT c.Id) > 0 OR COUNT(DISTINCT b.Id) > 0
),
PostAnalysis AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.ParentId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        COALESCE(p.ViewCount, 0) * COALESCE(p.Score, 0) AS ViewScoreProduct,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AnswerCount = 0 THEN 'Unanswered'
            WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN 'Answered'
            ELSE 'Other'
        END AS QuestionStatus,
        CASE 
            WHEN p.Score >= 100 THEN 'HighlyVoted'
            WHEN p.Score >= 10 THEN 'ModeratelyVoted'
            WHEN p.Score >= 0 THEN 'LowVoted'
            ELSE 'Negative'
        END AS ScoreCategory
    FROM Posts p
    WHERE p.CreationDate >= DATEADD(MONTH, -6, CURRENT_TIMESTAMP)
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count AS TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            WHEN t.Count > 10 THEN 'Niche'
            ELSE 'Rare'
        END AS PopularityLevel,
        CASE 
            WHEN t.IsRequired = 1 THEN 'Required'
            WHEN t.IsModeratorOnly = 1 THEN 'ModeratorOnly'
            ELSE 'Regular'
        END AS TagType
    FROM Tags t
    WHERE t.Count > 0
)
SELECT 
    'Performance Benchmark Results' AS ReportTitle,
    COUNT(DISTINCT qs.QuestionId) AS TotalQuestions,
    COUNT(DISTINCT uas.UserId) AS ActiveUsers,
    COUNT(DISTINCT pa.Id) AS TotalPosts,
    COUNT(DISTINCT ta.TagName) AS TotalTags,
    AVG(uas.Reputation) AS AvgUserReputation,
    AVG(uas.TotalScore) AS AvgUserTotalScore,
    MAX(pa.ViewScoreProduct) AS MaxViewScoreProduct,
    COUNT(*) OVER() AS BenchmarkCounter,
    CASE 
        WHEN AVG(uas.Reputation) > 10000 THEN 'High'
        WHEN AVG(uas.Reputation) > 5000 THEN 'Medium'
        ELSE 'Low'
    END AS ReputationLevel,
    STRING_AGG(
        CASE 
            WHEN qs.QuestionId IS NOT NULL THEN qs.Title
            ELSE NULL
        END, 
        ' | '
    ) AS SampleQuestions,
    COUNT(DISTINCT CASE WHEN pa.QuestionStatus = 'Answered' THEN pa.Id END) AS AnsweredQuestions,
    COUNT(DISTINCT CASE WHEN pa.QuestionStatus = 'Unanswered' THEN pa.Id END) AS UnansweredQuestions,
    COALESCE(
        (SELECT AVG(AnswerCount) FROM Posts WHERE PostTypeId = 1 AND ParentId IS NULL AND CreationDate >= DATEADD(MONTH, -1, CURRENT_TIMESTAMP)), 
        0
    ) AS AvgQuestionAnswerCount,
    MAX(uas.LastPostDate) AS MostRecentUserActivity,
    MIN(pa.CreationDate) AS OldestPost,
    MAX(pa.CreationDate) AS NewestPost,
    STDEV(pa.Score) AS ScoreStandardDeviation,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY pa.Score) AS MedianScore,
    COUNT(DISTINCT CASE WHEN ta.PopularityLevel = 'Popular' THEN ta.TagName END) AS PopularTags,
    COUNT(DISTINCT CASE WHEN ta.PopularityLevel = 'Moderate' THEN ta.TagName END) AS ModerateTags,
    COUNT(DISTINCT CASE WHEN ta.PopularityLevel = 'Niche' THEN ta.TagName END) AS NicheTags,
    COUNT(DISTINCT CASE WHEN ta.PopularityLevel = 'Rare' THEN ta.TagName END) AS RareTags,
    COUNT(DISTINCT CASE WHEN pa.ScoreCategory = 'HighlyVoted' THEN pa.Id END) AS HighlyVotedPosts,
    COUNT(DISTINCT CASE WHEN pa.ScoreCategory = 'ModeratelyVoted' THEN pa.Id END) AS ModeratelyVotedPosts,
    COUNT(DISTINCT CASE WHEN pa.ScoreCategory = 'LowVoted' THEN pa.Id END) AS LowVotedPosts,
    COUNT(DISTINCT CASE WHEN pa.ScoreCategory = 'Negative' THEN pa.Id END) AS NegativeVotedPosts,
    AVG(uas.AccountAgeDays) AS AvgAccountAgeDays,
    COALESCE(SUM(pa.ViewCount), 0) AS TotalViews,
    COALESCE(SUM(pa.AnswerCount), 0) AS TotalAnswersInAnalysis,
    COALESCE(SUM(pa.CommentCount), 0) AS TotalComments,
    COALESCE(SUM(pa.Score), 0) AS TotalScoreAcrossAllPosts,
    STRING_AGG(
        CASE 
            WHEN ta.TagName IS NOT NULL THEN ta.TagName
            ELSE NULL
        END, 
        ', '
    ) WITHIN GROUP (ORDER BY ta.Count DESC) AS TopTags,
    ROW_NUMBER() OVER (ORDER BY AVG(uas.Reputation) DESC) AS ReputationRank,
    DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT pa.Id) DESC) AS PostActivityRank,
    RANK() OVER (ORDER BY MAX(pa.CreationDate) DESC) AS RecentActivityRank
FROM QuestionHierarchy qs
FULL OUTER JOIN UserActivityStats uas ON qs.OwnerUserId = uas.UserId
FULL OUTER JOIN PostAnalysis pa ON qs.QuestionId = pa.Id OR uas.UserId = pa.OwnerUserId
FULL OUTER JOIN TagAnalysis ta ON qs.QuestionId = ta.ExcerptPostId OR qs.QuestionId = ta.WikiPostId
WHERE (qs.QuestionId IS NOT NULL OR uas.UserId IS NOT NULL OR pa.Id IS NOT NULL OR ta.TagName IS NOT NULL)
GROUP BY 
    uas.Reputation,
    uas.LastPostDate,
    pa.CreationDate,
    pa.ViewCount,
    pa.AnswerCount,
    pa.CommentCount,
    pa.Score,
    pa.QuestionStatus,
    pa.ScoreCategory,
    ta.PopularityLevel,
    ta.TagName
HAVING 
    COUNT(*) > 0 
    AND (COUNT(DISTINCT qs.QuestionId) > 0 OR COUNT(DISTINCT uas.UserId) > 0 OR COUNT(DISTINCT pa.Id) > 0 OR COUNT(DISTINCT ta.TagName) > 0)
ORDER BY 
    AVG(uas.Reputation) DESC,
    COUNT(DISTINCT pa.Id) DESC,
    MAX(pa.CreationDate) DESC
LIMIT 10000;
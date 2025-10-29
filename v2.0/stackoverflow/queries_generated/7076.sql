-- {"query": "7076.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2301} 
WITH PostStats AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.LastActivityDate,
        p.Title,
        p.Tags,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostType,
        COALESCE(p.Title, 'No Title') AS CleanTitle,
        COALESCE(p.Tags, '') AS CleanTags,
        CASE 
            WHEN p.Score > 0 THEN 'Positive'
            WHEN p.Score < 0 THEN 'Negative'
            ELSE 'Neutral'
        END AS ScoreCategory,
        DATEDIFF(day, p.CreationDate, p.LastActivityDate) AS DaysSinceCreation,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.ViewCount DESC) AS ViewRank,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS ScoreRank
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) 
      AND p.CreationDate >= '2020-01-01'
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        SUM(COALESCE(p.Score, 0)) AS TotalScore,
        AVG(COALESCE(p.Score, 0)) AS AvgScore,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        MAX(p.CreationDate) AS LastPostDate,
        ROW_NUMBER() OVER (ORDER BY SUM(COALESCE(p.Score, 0)) DESC) AS UserRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2019-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopUsers AS (
    SELECT UserId, DisplayName, Reputation, PostCount, CommentCount, BadgeCount
    FROM UserActivity
    WHERE UserRank <= 50
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 100 THEN 'Popular'
            WHEN t.Count > 50 THEN 'Moderate'
            ELSE 'Low'
        END AS PopularityLevel,
        RANK() OVER (ORDER BY t.Count DESC) AS TagRank,
        LAG(t.Count) OVER (ORDER BY t.Count DESC) - t.Count AS CountDifference
    FROM Tags t
    WHERE t.Count > 0
),
ComplexPostAnalysis AS (
    SELECT 
        ps.Id,
        ps.OwnerUserId,
        ps.PostTypeId,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.CreationDate,
        ps.LastActivityDate,
        ps.Title,
        ps.Tags,
        ps.PostType,
        ps.CleanTitle,
        ps.CleanTags,
        ps.ScoreCategory,
        ps.DaysSinceCreation,
        ps.ViewRank,
        ps.ScoreRank,
        CASE 
            WHEN ps.Score >= (SELECT AVG(Score) FROM PostStats) THEN 'AboveAverage'
            WHEN ps.Score >= (SELECT AVG(Score) - STDDEV(Score) FROM PostStats) THEN 'Average'
            ELSE 'BelowAverage'
        END AS ScorePerformance,
        COALESCE((SELECT COUNT(*) FROM Comments c WHERE c.PostId = ps.Id), 0) AS CommentCountFromCommentsTable,
        COALESCE((SELECT COUNT(*) FROM Posts p2 WHERE p2.ParentId = ps.Id), 0) AS ChildPostCount,
        CASE 
            WHEN ps.Tags IS NOT NULL AND ps.Tags != '' THEN 
                (SELECT COUNT(*) FROM unnest(string_to_array(substring(ps.Tags, 2, LENGTH(ps.Tags)-2), '><')) AS tag WHERE tag LIKE '%sql%')
            ELSE 0
        END AS SqlTagCount,
        CASE 
            WHEN ps.AnswerCount > 0 AND ps.Score > 0 THEN 
                CAST(ps.Score AS FLOAT) / CAST(ps.AnswerCount AS FLOAT)
            ELSE NULL
        END AS ScorePerAnswer,
        CASE 
            WHEN ps.ViewCount > 0 AND ps.AnswerCount > 0 THEN 
                CAST(ps.AnswerCount AS FLOAT) / CAST(ps.ViewCount AS FLOAT)
            ELSE NULL
        END AS AnswerToViewRatio
    FROM PostStats ps
    WHERE ps.ViewCount > 0
),
UserPostSummary AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.ViewCount AS UserViews,
        u.UpVotes,
        u.DownVotes,
        u.AccountId,
        COALESCE(SUM(p.Score), 0) AS TotalUserScore,
        COALESCE(COUNT(p.Id), 0) AS TotalPosts,
        MAX(p.CreationDate) AS LastPostDate,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.CreationDate DESC) AS PostSequence,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC, SUM(p.Score) DESC) AS UserScoreRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.ViewCount, u.UpVotes, u.DownVotes, u.AccountId
)
SELECT 
    'Performance Benchmark Results' AS ReportTitle,
    COUNT(DISTINCT ps.Id) AS TotalPosts,
    COUNT(DISTINCT ps.OwnerUserId) AS ActiveUsers,
    COUNT(DISTINCT ta.TagName) AS TotalTags,
    COUNT(DISTINCT ups.UserId) AS TotalUsers,
    AVG(CAST(ps.Score AS FLOAT)) AS AvgPostScore,
    AVG(CAST(ps.ViewCount AS FLOAT)) AS AvgViewCount,
    SUM(ps.AnswerCount) AS TotalAnswers,
    SUM(ps.CommentCount) AS TotalComments,
    SUM(ps.FavoriteCount) AS TotalFavorites,
    MIN(ps.CreationDate) AS EarliestPost,
    MAX(ps.LastActivityDate) AS LatestActivity,
    COUNT(DISTINCT CASE WHEN ps.PostType = 'Question' THEN ps.Id END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN ps.PostType = 'Answer' THEN ps.Id END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN ps.ScoreCategory = 'Positive' THEN ps.Id END) AS PositiveScorePosts,
    COUNT(DISTINCT CASE WHEN ps.ScoreCategory = 'Negative' THEN ps.Id END) AS NegativeScorePosts,
    COUNT(DISTINCT CASE WHEN ps.ScoreCategory = 'Neutral' THEN ps.Id END) AS NeutralScorePosts,
    AVG(CAST(ps.DaysSinceCreation AS FLOAT)) AS AvgDaysSinceCreation,
    COUNT(DISTINCT CASE WHEN ps.ViewRank <= 10 THEN ps.Id END) AS Top10ViewedPosts,
    COUNT(DISTINCT CASE WHEN ps.ScoreRank <= 10 THEN ps.Id END) AS Top10ScoredPosts,
    AVG(CAST(ta.Count AS FLOAT)) AS AvgTagCount,
    MAX(ta.Count) AS MaxTagCount,
    COUNT(DISTINCT CASE WHEN ups.UserScoreRank <= 10 THEN ups.UserId END) AS Top10ScoringUsers,
    AVG(CAST(ups.TotalUserScore AS FLOAT)) AS AvgUserScore,
    AVG(CAST(ups.TotalPosts AS FLOAT)) AS AvgUserPosts,
    COUNT(DISTINCT CASE WHEN ups.TotalPosts > 10 THEN ups.UserId END) AS UsersWithMoreThan10Posts,
    COUNT(DISTINCT CASE WHEN ups.TotalPosts BETWEEN 5 AND 10 THEN ups.UserId END) AS UsersWith5To10Posts,
    COUNT(DISTINCT CASE WHEN ups.TotalPosts < 5 THEN ups.UserId END) AS UsersWithLessThan5Posts,
    COUNT(DISTINCT CASE WHEN ta.PopularityLevel = 'Popular' THEN ta.TagName END) AS PopularTags,
    COUNT(DISTINCT CASE WHEN ta.PopularityLevel = 'Moderate' THEN ta.TagName END) AS ModerateTags,
    COUNT(DISTINCT CASE WHEN ta.PopularityLevel = 'Low' THEN ta.TagName END) AS LowTags,
    COUNT(DISTINCT CASE WHEN ps.SqlTagCount > 0 THEN ps.Id END) AS PostsWithSqlTags,
    COUNT(DISTINCT CASE WHEN ps.AnswerToViewRatio IS NOT NULL THEN ps.Id END) AS PostsWithValidRatios,
    AVG(CAST(ps.AnswerToViewRatio AS FLOAT)) AS AvgAnswerToViewRatio,
    COUNT(DISTINCT CASE WHEN ps.ScorePerAnswer IS NOT NULL THEN ps.Id END) AS PostsWithScorePerAnswer,
    AVG(CAST(ps.ScorePerAnswer AS FLOAT)) AS AvgScorePerAnswer,
    COUNT(DISTINCT CASE WHEN ps.ScorePerformance = 'AboveAverage' THEN ps.Id END) AS AboveAverageScorePosts,
    COUNT(DISTINCT CASE WHEN ps.ScorePerformance = 'Average' THEN ps.Id END) AS AverageScorePosts,
    COUNT(DISTINCT CASE WHEN ps.ScorePerformance = 'BelowAverage' THEN ps.Id END) AS BelowAverageScorePosts,
    COUNT(*) OVER() AS TotalBenchmarkRows
FROM ComplexPostAnalysis ps
FULL OUTER JOIN TagAnalysis ta ON 1=1
FULL OUTER JOIN UserPostSummary ups ON 1=1
GROUP BY 
    ps.Id,
    ta.TagName,
    ups.UserId
HAVING COUNT(*) > 0
ORDER BY 
    COUNT(DISTINCT ps.Id) DESC,
    COUNT(DISTINCT ta.TagName) DESC,
    COUNT(DISTINCT ups.UserId) DESC;

-- NOTE: This query is intentionally resource-intensive for benchmarking purposes.
-- It includes:
-- - Multiple CTEs with complex logic
-- - Outer joins across different tables
-- - Correlated subqueries in CASE expressions
-- - Window functions (ROW_NUMBER, RANK, DENSE_RANK)
-- - Set operators (FULL OUTER JOIN)
-- - Complex predicates and calculations using window functions
-- - String manipulation with substring and unnest
-- - NULL handling with COALESCE and CASE expressions
-- - Aggregation across multiple tables at various levels
-- - Multi-level nesting of subqueries
-- - Multiple GROUP BY and HAVING clauses
-- - Mathematical calculations and ratios
-- - Date arithmetic and comparisons
-- - Multiple conditional logic structures
-- - Performance-oriented constructs with deliberate complexity
-- {"query": "7471.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2877} 
WITH UserStats AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.DisplayName,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) as TotalQuestionScore,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) as TotalAnswerScore,
        MAX(p.CreationDate) as LatestPostDate,
        MAX(c.CreationDate) as LatestCommentDate,
        MAX(b.Date) as LatestBadgeDate,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') as AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        COUNT(p.Id) as PostCount,
        AVG(p.Score) as AvgScore,
        STRING_AGG(DISTINCT u.DisplayName, ', ') as Contributors
    FROM Tags t
    LEFT JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE t.Count > 50
    GROUP BY t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId
),
UserActivity AS (
    SELECT 
        ps.UserId,
        ps.Reputation,
        ps.DisplayName,
        ps.PostCount,
        ps.QuestionCount,
        ps.AnswerCount,
        ps.TotalQuestionScore,
        ps.TotalAnswerScore,
        ps.LatestPostDate,
        ps.LatestCommentDate,
        ps.LatestBadgeDate,
        ps.AllTags,
        ROW_NUMBER() OVER (ORDER BY ps.Reputation DESC) as RankByReputation,
        ROW_NUMBER() OVER (ORDER BY ps.PostCount DESC) as RankByPostCount,
        RANK() OVER (ORDER BY ps.TotalQuestionScore DESC) as RankByQuestionScore,
        DENSE_RANK() OVER (ORDER BY ps.TotalAnswerScore DESC) as RankByAnswerScore,
        NTILE(100) OVER (ORDER BY ps.Reputation) as PercentileByReputation,
        LAG(ps.Reputation, 1) OVER (ORDER BY ps.Reputation) as PrevReputation,
        LEAD(ps.Reputation, 1) OVER (ORDER BY ps.Reputation) as NextReputation,
        AVG(ps.Reputation) OVER (ORDER BY ps.Reputation ROWS BETWEEN 5 PRECEDING AND 5 FOLLOWING) as MovingAvgReputation
    FROM UserStats ps
),
TopUsers AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.PostCount,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.TotalQuestionScore,
        ua.TotalAnswerScore,
        ua.RankByReputation,
        ua.RankByPostCount,
        ua.RankByQuestionScore,
        ua.RankByAnswerScore,
        ua.PercentileByReputation,
        ua.MovingAvgReputation,
        CASE 
            WHEN ua.Reputation > 100000 THEN 'Elite User'
            WHEN ua.Reputation > 10000 THEN 'Advanced User'
            WHEN ua.Reputation > 1000 THEN 'Regular User'
            ELSE 'New User'
        END as UserLevel,
        CASE 
            WHEN ua.PostCount > 1000 THEN 'Highly Active'
            WHEN ua.PostCount > 500 THEN 'Active'
            WHEN ua.PostCount > 100 THEN 'Moderate'
            ELSE 'Casual'
        END as ActivityLevel,
        DATEDIFF('DAY', ua.LatestPostDate, CURRENT_DATE) as DaysSinceLastPost,
        CASE 
            WHEN DATEDIFF('DAY', ua.LatestPostDate, CURRENT_DATE) < 30 THEN 'Very Active'
            WHEN DATEDIFF('DAY', ua.LatestPostDate, CURRENT_DATE) < 90 THEN 'Active'
            WHEN DATEDIFF('DAY', ua.LatestPostDate, CURRENT_DATE) < 365 THEN 'Moderate'
            ELSE 'Inactive'
        END as PostingFrequency,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) OVER (PARTITION BY ua.UserId), 0) as QuestionsByUser,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY ua.UserId), 0) as AnswersByUser,
        COALESCE(AVG(p.Score) OVER (PARTITION BY ua.UserId), 0) as AvgScoreByUser
    FROM UserActivity ua
    LEFT JOIN Posts p ON ua.UserId = p.OwnerUserId
    WHERE ua.Reputation > 10000
    GROUP BY 
        ua.UserId, ua.DisplayName, ua.Reputation, ua.PostCount, 
        ua.QuestionCount, ua.AnswerCount, ua.TotalQuestionScore, 
        ua.TotalAnswerScore, ua.RankByReputation, ua.RankByPostCount, 
        ua.RankByQuestionScore, ua.RankByAnswerScore, ua.PercentileByReputation, 
        ua.MovingAvgReputation, ua.LatestPostDate
),
QuestionStats AS (
    SELECT 
        p.Id as QuestionId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        u.DisplayName as OwnerName,
        p.OwnerUserId,
        SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2) as Tags,
        EXTRACT(YEAR FROM p.CreationDate) as YearCreated,
        EXTRACT(MONTH FROM p.CreationDate) as MonthCreated,
        CASE 
            WHEN p.Score > 100 THEN 'Highly Voted'
            WHEN p.Score > 50 THEN 'Well Voted'
            WHEN p.Score > 10 THEN 'Moderately Voted'
            ELSE 'Low Voted'
        END as VoteCategory,
        CASE 
            WHEN p.ViewCount > 5000 THEN 'Viral'
            WHEN p.ViewCount > 1000 THEN 'Popular'
            WHEN p.ViewCount > 100 THEN 'Moderate'
            ELSE 'Low Traffic'
        END as TrafficCategory,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC) as RankByScore,
        DENSE_RANK() OVER (ORDER BY p.ViewCount DESC) as RankByViews,
        PERCENT_RANK() OVER (ORDER BY p.Score) as PercentileByScore,
        NTILE(5) OVER (ORDER BY p.CreationDate) as QuarterCreated,
        LAG(p.Score, 1) OVER (ORDER BY p.Score) as PrevScore,
        LEAD(p.Score, 1) OVER (ORDER BY p.Score) as NextScore,
        AVG(p.Score) OVER (ORDER BY p.CreationDate ROWS BETWEEN 10 PRECEDING AND 10 FOLLOWING) as MovingAvgScore
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
),
AnswerStats AS (
    SELECT 
        p.Id as AnswerId,
        p.ParentId as QuestionId,
        p.Score,
        p.CreationDate,
        u.DisplayName as OwnerName,
        p.OwnerUserId,
        p.Body,
        CASE 
            WHEN p.Score > 50 THEN 'Excellent Answer'
            WHEN p.Score > 20 THEN 'Good Answer'
            WHEN p.Score > 5 THEN 'Fair Answer'
            ELSE 'Basic Answer'
        END as QualityCategory,
        ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC) as AnswerRank,
        COUNT(*) OVER (PARTITION BY p.ParentId) as TotalAnswersForQuestion,
        AVG(p.Score) OVER (PARTITION BY p.ParentId) as AvgScoreForQuestion,
        RANK() OVER (ORDER BY p.Score DESC) as RankByScore
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 2
    AND p.Score > 0
)
SELECT 
    'Overall Statistics' as Category,
    COUNT(*) as TotalRecords,
    COUNT(DISTINCT u.Id) as TotalUsers,
    COUNT(DISTINCT p.Id) as TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as TotalAnswers,
    COUNT(DISTINCT c.Id) as TotalComments,
    COUNT(DISTINCT b.Id) as TotalBadges,
    AVG(u.Reputation) as AvgReputation,
    AVG(p.Score) as AvgPostScore,
    MAX(u.Reputation) as MaxReputation,
    MIN(u.Reputation) as MinReputation,
    SUM(p.ViewCount) as TotalViews,
    SUM(p.FavoriteCount) as TotalFavorites,
    CAST(SUM(CASE WHEN p.CreationDate > CURRENT_DATE - INTERVAL '30' DAY THEN 1 ELSE 0 END) AS REAL) / COUNT(*) * 100 as RecentPostPercentage
FROM Users u
FULL OUTER JOIN Posts p ON 1=1
FULL OUTER JOIN Comments c ON 1=1
FULL OUTER JOIN Badges b ON 1=1
WHERE u.Id IS NOT NULL OR p.Id IS NOT NULL OR c.Id IS NOT NULL OR b.Id IS NOT NULL

UNION ALL

SELECT 
    'Top Users Analysis' as Category,
    COUNT(*) as TotalRecords,
    COUNT(DISTINCT tu.UserId) as TotalUsers,
    0 as TotalPosts,
    0 as TotalQuestions,
    0 as TotalAnswers,
    0 as TotalComments,
    0 as TotalBadges,
    AVG(tu.Reputation) as AvgReputation,
    NULL as AvgPostScore,
    MAX(tu.Reputation) as MaxReputation,
    MIN(tu.Reputation) as MinReputation,
    NULL as TotalViews,
    NULL as TotalFavorites,
    CAST(SUM(CASE WHEN tu.LatestPostDate > CURRENT_DATE - INTERVAL '30' DAY THEN 1 ELSE 0 END) AS REAL) / COUNT(*) * 100 as RecentPostPercentage
FROM TopUsers tu

UNION ALL

SELECT 
    'Tag Analysis' as Category,
    COUNT(*) as TotalRecords,
    0 as TotalUsers,
    COUNT(DISTINCT ta.TagName) as TotalPosts,
    0 as TotalQuestions,
    0 as TotalAnswers,
    0 as TotalComments,
    0 as TotalBadges,
    NULL as AvgReputation,
    NULL as AvgPostScore,
    NULL as MaxReputation,
    NULL as MinReputation,
    NULL as TotalViews,
    NULL as TotalFavorites,
    NULL as RecentPostPercentage
FROM TagAnalysis ta

UNION ALL

SELECT 
    'Question Analysis' as Category,
    COUNT(*) as TotalRecords,
    0 as TotalUsers,
    COUNT(DISTINCT qs.QuestionId) as TotalPosts,
    COUNT(DISTINCT qs.QuestionId) as TotalQuestions,
    0 as TotalAnswers,
    0 as TotalComments,
    0 as TotalBadges,
    NULL as AvgReputation,
    AVG(qs.Score) as AvgPostScore,
    MAX(qs.Score) as MaxReputation,
    MIN(qs.Score) as MinReputation,
    SUM(qs.ViewCount) as TotalViews,
    SUM(qs.FavoriteCount) as TotalFavorites,
    CAST(SUM(CASE WHEN qs.CreationDate > CURRENT_DATE - INTERVAL '30' DAY THEN 1 ELSE 0 END) AS REAL) / COUNT(*) * 100 as RecentPostPercentage
FROM QuestionStats qs

UNION ALL

SELECT 
    'Answer Analysis' as Category,
    COUNT(*) as TotalRecords,
    0 as TotalUsers,
    COUNT(DISTINCT asa.AnswerId) as TotalPosts,
    0 as TotalQuestions,
    COUNT(DISTINCT asa.AnswerId) as TotalAnswers,
    0 as TotalComments,
    0 as TotalBadges,
    NULL as AvgReputation,
    AVG(asa.Score) as AvgPostScore,
    MAX(asa.Score) as MaxReputation,
    MIN(asa.Score) as MinReputation,
    NULL as TotalViews,
    NULL as TotalFavorites,
    CAST(SUM(CASE WHEN asa.CreationDate > CURRENT_DATE - INTERVAL '30' DAY THEN 1 ELSE 0 END) AS REAL) / COUNT(*) * 100 as RecentPostPercentage
FROM AnswerStats asa

ORDER BY Category;
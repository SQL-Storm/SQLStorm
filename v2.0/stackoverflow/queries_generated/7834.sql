-- {"query": "7834.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1652} 
WITH UserStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        MAX(p.CreationDate) as LastPostDate,
        CASE 
            WHEN u.Reputation >= 10000 THEN 'Elite'
            WHEN u.Reputation >= 1000 THEN 'Expert'
            WHEN u.Reputation >= 100 THEN 'Novice'
            ELSE 'Beginner'
        END as ReputationLevel,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        COALESCE(SUM(p.ViewCount), 0) as TotalViews,
        ROUND(CAST(SUM(p.Score) AS FLOAT) / NULLIF(COUNT(p.Id), 0), 2) as AvgPostScore,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') as AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TopPosts AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Tags,
        p.PostTypeId,
        p.AnswerCount,
        p.CommentCount,
        u.DisplayName as OwnerName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) as ScoreRank,
        DENSE_RANK() OVER (ORDER BY p.ViewCount DESC) as ViewRank,
        NTILE(4) OVER (ORDER BY p.Score DESC) as ScoreQuartile,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 'Accepted'
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NULL THEN 'Unanswered'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostStatus
    FROM Posts p
    INNER JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.Score IS NOT NULL AND p.CreationDate >= '2020-01-01'
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            WHEN t.Count > 10 THEN 'Niche'
            ELSE 'Rare'
        END as TagPopularity,
        t.IsRequired,
        t.IsModeratorOnly,
        (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') as RelatedPostCount
    FROM Tags t
    WHERE t.TagName IS NOT NULL
),
PerformanceMetrics AS (
    SELECT 
        'Overall' as MetricType,
        COUNT(*) as TotalUsers,
        COUNT(DISTINCT u.Id) as DistinctUsers,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT p.OwnerUserId) as ActivePosterCount,
        COUNT(DISTINCT c.Id) as TotalComments,
        ROUND(AVG(u.Reputation), 2) as AvgReputation,
        ROUND(AVG(p.Score), 2) as AvgPostScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    UNION ALL
    SELECT 
        'HighScoreUsers' as MetricType,
        COUNT(*) as TotalUsers,
        COUNT(DISTINCT u.Id) as DistinctUsers,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT p.OwnerUserId) as ActivePosterCount,
        COUNT(DISTINCT c.Id) as TotalComments,
        ROUND(AVG(u.Reputation), 2) as AvgReputation,
        ROUND(AVG(p.Score), 2) as AvgPostScore
    FROM Users u
    INNER JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    WHERE u.Reputation >= 10000
)
SELECT 
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.ReputationLevel,
    us.PostCount,
    us.CommentCount,
    us.BadgeCount,
    us.TotalScore,
    us.TotalViews,
    us.AvgPostScore,
    us.LastPostDate,
    tp.ScoreRank,
    tp.ViewRank,
    tp.ScoreQuartile,
    tp.PostStatus,
    tp.Title as TopPostTitle,
    tp.Score as TopPostScore,
    tp.ViewCount as TopPostViews,
    ta.TagName,
    ta.TagCount,
    ta.TagPopularity,
    pm.MetricType,
    pm.TotalUsers,
    pm.DistinctUsers,
    pm.TotalPosts,
    pm.ActivePosterCount,
    pm.TotalComments,
    pm.AvgReputation,
    pm.AvgPostScore,
    CASE 
        WHEN us.PostCount > 0 AND us.Reputation > 0 THEN 
            ROUND(CAST(us.PostCount AS FLOAT) * 100.0 / NULLIF(us.Reputation, 0), 2)
        ELSE 0 
    END as PostsPerReputation,
    COALESCE(LEFT(us.AllTags, 100), 'No tags') as SampleTags,
    CASE 
        WHEN us.PostCount > 10 AND us.BadgeCount > 5 THEN 'Active Contributor'
        WHEN us.PostCount > 5 AND us.BadgeCount > 2 THEN 'Regular Contributor'
        WHEN us.PostCount > 0 THEN 'Occasional Poster'
        ELSE 'Inactive'
    END as ContributionLevel,
    RANK() OVER (ORDER BY us.TotalScore DESC) as OverallScoreRank,
    DENSE_RANK() OVER (ORDER BY us.Reputation DESC) as ReputationRank,
    DATEDIFF(day, us.LastPostDate, CURRENT_TIMESTAMP) as DaysSinceLastPost,
    CASE 
        WHEN DATEDIFF(day, us.LastPostDate, CURRENT_TIMESTAMP) > 365 THEN 'Inactive for over a year'
        WHEN DATEDIFF(day, us.LastPostDate, CURRENT_TIMESTAMP) > 180 THEN 'Inactive for 6+ months'
        WHEN DATEDIFF(day, us.LastPostDate, CURRENT_TIMESTAMP) > 90 THEN 'Inactive for 3+ months'
        WHEN DATEDIFF(day, us.LastPostDate, CURRENT_TIMESTAMP) > 30 THEN 'Inactive for month'
        ELSE 'Active'
    END as ActivityStatus
FROM UserStats us
LEFT JOIN TopPosts tp ON us.UserId = tp.OwnerUserId AND tp.ScoreRank <= 5
LEFT JOIN TagAnalysis ta ON ta.TagName IN (
    SELECT unnest(string_to_array(us.AllTags, ', ')) 
    FROM UserStats us2 
    WHERE us2.UserId = us.UserId AND us2.AllTags IS NOT NULL
)
JOIN PerformanceMetrics pm ON pm.MetricType = 'Overall'
WHERE us.UserId IS NOT NULL
    AND (tp.PostId IS NOT NULL OR ta.TagName IS NOT NULL OR pm.MetricType IS NOT NULL)
    AND (us.Reputation >= 100 OR us.PostCount >= 1 OR us.CommentCount >= 1)
ORDER BY us.TotalScore DESC, us.Reputation DESC
LIMIT 10000;
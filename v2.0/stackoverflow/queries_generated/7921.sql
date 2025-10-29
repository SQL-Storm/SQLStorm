-- {"query": "7921.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 4119} 
WITH UserActivityStats AS (
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
        MAX(c.CreationDate) as LastCommentDate,
        MAX(b.Date) as LastBadgeDate,
        CASE 
            WHEN u.Reputation > 10000 THEN 'Elite'
            WHEN u.Reputation > 5000 THEN 'Expert'
            WHEN u.Reputation > 1000 THEN 'Advanced'
            ELSE 'Beginner'
        END as ReputationTier,
        CASE 
            WHEN u.Views > 10000 THEN 'Highly Viewed'
            WHEN u.Views > 5000 THEN 'Well Viewed'
            WHEN u.Views > 1000 THEN 'Moderately Viewed'
            ELSE 'Low Viewed'
        END as ViewTier,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id END) as WikiCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TopUsersByReputation AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        PostCount,
        CommentCount,
        BadgeCount,
        LastPostDate,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, PostCount DESC) as RankByReputation
    FROM UserActivityStats
),
TagStatistics AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 500 THEN 'Well Known'
            WHEN t.Count > 100 THEN 'Known'
            ELSE 'Unknown'
        END as PopularityLevel,
        DENSE_RANK() OVER (ORDER BY t.Count DESC) as PopularityRank
    FROM Tags t
),
PostStatsWithAggregates AS (
    SELECT 
        p.Id as PostId,
        p.PostTypeId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.LastActivityDate,
        p.OwnerUserId,
        u.DisplayName as OwnerDisplayName,
        u.Reputation as OwnerReputation,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            WHEN p.PostTypeId = 5 THEN 'TagWiki'
            ELSE 'Other'
        END as PostTypeDescription,
        CASE 
            WHEN p.ViewCount > 10000 THEN 'Viral'
            WHEN p.ViewCount > 5000 THEN 'Highly Popular'
            WHEN p.ViewCount > 1000 THEN 'Popular'
            WHEN p.ViewCount > 500 THEN 'Moderate'
            ELSE 'Low'
        END as PopularityCategory,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as UserPostRank,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as AvgScorePerUser,
        SUM(p.ViewCount) OVER (PARTITION BY p.OwnerUserId) as TotalViewsPerUser,
        RANK() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) as PostScoreRank,
        NTILE(4) OVER (ORDER BY p.Score DESC) as ScoreQuartile
    FROM Posts p
    INNER JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2, 5) -- Only questions, answers, and tag wikis
    AND p.CreationDate >= DATEADD(YEAR, -2, GETDATE())
),
ComplexAnalytics AS (
    SELECT 
        ps.PostId,
        ps.PostTypeId,
        ps.Title,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.OwnerUserId,
        ps.OwnerDisplayName,
        ps.OwnerReputation,
        ps.PostTypeDescription,
        ps.PopularityCategory,
        ps.UserPostRank,
        ps.AvgScorePerUser,
        ps.TotalViewsPerUser,
        ps.PostScoreRank,
        ps.ScoreQuartile,
        ps.CreationDate,
        ps.LastActivityDate,
        CASE 
            WHEN ps.PostScoreRank <= 100 THEN 'Top 100'
            WHEN ps.PostScoreRank <= 1000 THEN 'Top 1000'
            ELSE 'Other'
        END as RankCategory,
        -- Complex calculated fields for benchmarking
        CAST(NULLIF(ps.ViewCount, 0) AS FLOAT) / NULLIF(ps.Score, 0) as AvgViewsPerScore,
        (ps.Score * 1.5 + ps.AnswerCount * 0.8 + ps.CommentCount * 0.3 + ps.FavoriteCount * 2.0) as ComplexScoreMetric,
        CAST(DATEDIFF(DAY, ps.CreationDate, ps.LastActivityDate) AS FLOAT) / NULLIF(DATEDIFF(DAY, ps.CreationDate, GETDATE()), 0) as ActivityLifetimeRatio,
        DENSE_RANK() OVER (ORDER BY ps.AnswerCount DESC) as AnswerRank,
        DENSE_RANK() OVER (ORDER BY ps.CommentCount DESC) as CommentRank,
        -- Correlated subquery to calculate user's reputation percentile
        (SELECT COUNT(*) 
         FROM Users u2 
         WHERE u2.Reputation >= ps.OwnerReputation) * 100.0 / (SELECT COUNT(*) FROM Users) as ReputationPercentile
    FROM PostStatsWithAggregates ps
),
UserMetrics AS (
    SELECT 
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.Views,
        uas.UpVotes,
        uas.DownVotes,
        uas.PostCount,
        uas.CommentCount,
        uas.BadgeCount,
        uas.LastPostDate,
        uas.LastCommentDate,
        uas.LastBadgeDate,
        uas.ReputationTier,
        uas.ViewTier,
        uas.QuestionCount,
        uas.AnswerCount,
        uas.WikiCount,
        -- Aggregates and complex calculations
        AVG(uas.PostCount) OVER (ORDER BY uas.Reputation ROWS BETWEEN 10 PRECEDING AND 10 FOLLOWING) as MovingAvgPostCount,
        MAX(uas.Reputation) OVER (ORDER BY uas.Views ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as MaxReputation,
        CASE 
            WHEN uas.Reputation > (SELECT AVG(Reputation) FROM Users) THEN 'Above Average'
            WHEN uas.Reputation < (SELECT AVG(Reputation) FROM Users) THEN 'Below Average'
            ELSE 'Average'
        END as ReputationStatus,
        -- Window function with multiple PARTITION BY clauses
        ROW_NUMBER() OVER (PARTITION BY uas.ReputationTier ORDER BY uas.PostCount DESC, uas.Reputation DESC) as TierRank,
        -- Set operation example (UNION with multiple selects)
        'User' as EntityType
    FROM UserActivityStats uas
    WHERE uas.PostCount > 0
)
-- Main complex query with multiple joins, clauses, and constructions
SELECT 
    tm.UserId,
    tm.DisplayName,
    tm.Reputation,
    tm.Views,
    tm.PostCount,
    tm.CommentCount,
    tm.BadgeCount,
    tm.ReputationTier,
    tm.ViewTier,
    tm.QuestionCount,
    tm.AnswerCount,
    tm.WikiCount,
    tm.MovingAvgPostCount,
    tm.MaxReputation,
    tm.ReputationStatus,
    tm.TierRank,
    ps.PostId,
    ps.Title,
    ps.Score,
    ps.ViewCount,
    ps.AnswerCount as PostAnswerCount,
    ps.CommentCount as PostCommentCount,
    ps.FavoriteCount,
    ps.PostTypeDescription,
    ps.PopularityCategory,
    ps.AvgScorePerUser,
    ps.TotalViewsPerUser,
    ps.PostScoreRank,
    ps.ScoreQuartile,
    ps.RankCategory,
    ps.ComplexScoreMetric,
    ps.ActivityLifetimeRatio,
    ps.AnswerRank,
    ps.CommentRank,
    ps.ReputationPercentile,
    ts.TagName,
    ts.TagCount,
    ts.PopularityLevel,
    ts.PopularityRank,
    pu.Reputation as TopUserReputation,
    pu.DisplayName as TopUserDisplayName,
    pu.RankByReputation,
    -- String manipulations and complex expressions
    UPPER(SUBSTRING(tm.DisplayName, 1, 1)) + LOWER(SUBSTRING(tm.DisplayName, 2, LEN(tm.DisplayName) - 1)) as FormattedName,
    COALESCE(ts.TagName, 'No Tags') as EffectiveTagName,
    CASE 
        WHEN ps.ComplexScoreMetric > 50 THEN 'Highly Engaging'
        WHEN ps.ComplexScoreMetric > 25 THEN 'Moderately Engaging'
        WHEN ps.ComplexScoreMetric > 10 THEN 'Low Engagement'
        ELSE 'Minimal Engagement'
    END as EngagementLevel,
    -- Calculated timestamp differences
    DATEDIFF(DAY, tm.LastPostDate, GETDATE()) as DaysSinceLastPost,
    DATEDIFF(DAY, tm.LastCommentDate, GETDATE()) as DaysSinceLastComment,
    DATEDIFF(DAY, tm.LastBadgeDate, GETDATE()) as DaysSinceLastBadge,
    -- NULL handling with CASE statements
    CASE 
        WHEN ps.ViewCount IS NULL THEN 'View Count Not Available'
        WHEN ps.ViewCount > 10000 THEN 'Very High View Count'
        WHEN ps.ViewCount > 5000 THEN 'High View Count'
        WHEN ps.ViewCount > 1000 THEN 'Moderate View Count'
        ELSE 'Low View Count'
    END as ViewCategory,
    -- Complex boolean logic and predicates
    CASE 
        WHEN tm.PostCount > 100 AND tm.ViewCount > 10000 AND tm.Reputation > 5000 THEN 1
        WHEN tm.PostCount > 50 AND tm.ViewCount > 5000 AND tm.Reputation > 2000 THEN 1
        ELSE 0
    END as HighPerformingUser,
    -- Multiple joins in FROM clause with complex join conditions
    NULL as DummyColumn1,
    NULL as DummyColumn2,
    NULL as DummyColumn3,
    NULL as DummyColumn4,
    -- Set operations
    'ResultSetA' as SourceSet
FROM UserMetrics tm
INNER JOIN PostStatsWithAggregates ps ON tm.UserId = ps.OwnerUserId
INNER JOIN UserMetrics pu ON pu.RankByReputation = 1
LEFT JOIN TagStatistics ts ON ts.PopularityRank BETWEEN 1 AND 5 -- Top 5 popular tags
WHERE ps.PostScoreRank BETWEEN 1 AND 1000
AND ps.Score > 10
AND (ps.ViewCount > 100 OR ps.CommentCount > 5)
AND tm.Reputation > 1000
AND (ps.ComplexScoreMetric > 20 OR ps.ActivityLifetimeRatio > 0.5)
UNION ALL
SELECT 
    tm.UserId,
    tm.DisplayName,
    tm.Reputation,
    tm.Views,
    tm.PostCount,
    tm.CommentCount,
    tm.BadgeCount,
    tm.ReputationTier,
    tm.ViewTier,
    tm.QuestionCount,
    tm.AnswerCount,
    tm.WikiCount,
    tm.MovingAvgPostCount,
    tm.MaxReputation,
    tm.ReputationStatus,
    tm.TierRank,
    ps.PostId,
    ps.Title,
    ps.Score,
    ps.ViewCount,
    ps.AnswerCount as PostAnswerCount,
    ps.CommentCount as PostCommentCount,
    ps.FavoriteCount,
    ps.PostTypeDescription,
    ps.PopularityCategory,
    ps.AvgScorePerUser,
    ps.TotalViewsPerUser,
    ps.PostScoreRank,
    ps.ScoreQuartile,
    ps.RankCategory,
    ps.ComplexScoreMetric,
    ps.ActivityLifetimeRatio,
    ps.AnswerRank,
    ps.CommentRank,
    ps.ReputationPercentile,
    ts.TagName,
    ts.TagCount,
    ts.PopularityLevel,
    ts.PopularityRank,
    pu.Reputation as TopUserReputation,
    pu.DisplayName as TopUserDisplayName,
    pu.RankByReputation,
    UPPER(SUBSTRING(tm.DisplayName, 1, 1)) + LOWER(SUBSTRING(tm.DisplayName, 2, LEN(tm.DisplayName) - 1)) as FormattedName,
    COALESCE(ts.TagName, 'No Tags') as EffectiveTagName,
    CASE 
        WHEN ps.ComplexScoreMetric > 50 THEN 'Highly Engaging'
        WHEN ps.ComplexScoreMetric > 25 THEN 'Moderately Engaging'
        WHEN ps.ComplexScoreMetric > 10 THEN 'Low Engagement'
        ELSE 'Minimal Engagement'
    END as EngagementLevel,
    DATEDIFF(DAY, tm.LastPostDate, GETDATE()) as DaysSinceLastPost,
    DATEDIFF(DAY, tm.LastCommentDate, GETDATE()) as DaysSinceLastComment,
    DATEDIFF(DAY, tm.LastBadgeDate, GETDATE()) as DaysSinceLastBadge,
    CASE 
        WHEN ps.ViewCount IS NULL THEN 'View Count Not Available'
        WHEN ps.ViewCount > 10000 THEN 'Very High View Count'
        WHEN ps.ViewCount > 5000 THEN 'High View Count'
        WHEN ps.ViewCount > 1000 THEN 'Moderate View Count'
        ELSE 'Low View Count'
    END as ViewCategory,
    CASE 
        WHEN tm.PostCount > 100 AND tm.ViewCount > 10000 AND tm.Reputation > 5000 THEN 1
        WHEN tm.PostCount > 50 AND tm.ViewCount > 5000 AND tm.Reputation > 2000 THEN 1
        ELSE 0
    END as HighPerformingUser,
    NULL as DummyColumn1,
    NULL as DummyColumn2,
    NULL as DummyColumn3,
    NULL as DummyColumn4,
    'ResultSetB' as SourceSet
FROM UserMetrics tm
INNER JOIN ComplexAnalytics ps ON tm.UserId = ps.OwnerUserId
INNER JOIN UserMetrics pu ON pu.RankByReputation = 1
LEFT JOIN TagStatistics ts ON ts.PopularityRank BETWEEN 1 AND 5
WHERE ps.PostScoreRank BETWEEN 50 AND 2000
AND ps.Score > 5
AND (ps.ViewCount > 50 OR ps.CommentCount > 3)
AND tm.Reputation > 500
AND tm.PostCount > 10
AND ps.ComplexScoreMetric > 15
UNION ALL
SELECT 
    tm.UserId,
    tm.DisplayName,
    tm.Reputation,
    tm.Views,
    tm.PostCount,
    tm.CommentCount,
    tm.BadgeCount,
    tm.ReputationTier,
    tm.ViewTier,
    tm.QuestionCount,
    tm.AnswerCount,
    tm.WikiCount,
    tm.MovingAvgPostCount,
    tm.MaxReputation,
    tm.ReputationStatus,
    tm.TierRank,
    ps.PostId,
    ps.Title,
    ps.Score,
    ps.ViewCount,
    ps.AnswerCount as PostAnswerCount,
    ps.CommentCount as PostCommentCount,
    ps.FavoriteCount,
    ps.PostTypeDescription,
    ps.PopularityCategory,
    ps.AvgScorePerUser,
    ps.TotalViewsPerUser,
    ps.PostScoreRank,
    ps.ScoreQuartile,
    ps.RankCategory,
    ps.ComplexScoreMetric,
    ps.ActivityLifetimeRatio,
    ps.AnswerRank,
    ps.CommentRank,
    ps.ReputationPercentile,
    ts.TagName,
    ts.TagCount,
    ts.PopularityLevel,
    ts.PopularityRank,
    pu.Reputation as TopUserReputation,
    pu.DisplayName as TopUserDisplayName,
    pu.RankByReputation,
    UPPER(SUBSTRING(tm.DisplayName, 1, 1)) + LOWER(SUBSTRING(tm.DisplayName, 2, LEN(tm.DisplayName) - 1)) as FormattedName,
    COALESCE(ts.TagName, 'No Tags') as EffectiveTagName,
    CASE 
        WHEN ps.ComplexScoreMetric > 50 THEN 'Highly Engaging'
        WHEN ps.ComplexScoreMetric > 25 THEN 'Moderately Engaging'
        WHEN ps.ComplexScoreMetric > 10 THEN 'Low Engagement'
        ELSE 'Minimal Engagement'
    END as EngagementLevel,
    DATEDIFF(DAY, tm.LastPostDate, GETDATE()) as DaysSinceLastPost,
    DATEDIFF(DAY, tm.LastCommentDate, GETDATE()) as DaysSinceLastComment,
    DATEDIFF(DAY, tm.LastBadgeDate, GETDATE()) as DaysSinceLastBadge,
    CASE 
        WHEN ps.ViewCount IS NULL THEN 'View Count Not Available'
        WHEN ps.ViewCount > 10000 THEN 'Very High View Count'
        WHEN ps.ViewCount > 5000 THEN 'High View Count'
        WHEN ps.ViewCount > 1000 THEN 'Moderate View Count'
        ELSE 'Low View Count'
    END as ViewCategory,
    CASE 
        WHEN tm.PostCount > 100 AND tm.ViewCount > 10000 AND tm.Reputation > 5000 THEN 1
        WHEN tm.PostCount > 50 AND tm.ViewCount > 5000 AND tm.Reputation > 2000 THEN 1
        ELSE 0
    END as HighPerformingUser,
    NULL as DummyColumn1,
    NULL as DummyColumn2,
    NULL as DummyColumn3,
    NULL as DummyColumn4,
    'ResultSetC' as SourceSet
FROM UserMetrics tm
INNER JOIN PostStatsWithAggregates ps ON tm.UserId = ps.OwnerUserId
INNER JOIN UserMetrics pu ON pu.RankByReputation = 1
LEFT JOIN TagStatistics ts ON ts.PopularityRank BETWEEN 1 AND 5
WHERE ps.PostScoreRank BETWEEN 100 AND 1000
AND ps.ViewCount > 1000
AND ps.Score > 20
AND tm.Reputation > 1000
AND ps.ComplexScoreMetric > 25
AND tm.PostCount > 50
ORDER BY ComplexScoreMetric DESC, Reputation DESC, ViewCount DESC, PostScoreRank ASC;
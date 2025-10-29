-- {"query": "7256.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1967} 
WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        p.CreationDate,
        p.LastActivityDate,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
        LAG(p.ViewCount) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_views,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) as score_rank,
        NTILE(100) OVER (ORDER BY p.Score) as score_percentile
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserActivity AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        AVG(p.Score) as AvgPostScore,
        MAX(p.CreationDate) as LastPostDate,
        CASE WHEN COUNT(DISTINCT p.Id) > 0 THEN 'Active' ELSE 'Inactive' END as ActivityStatus,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') as AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 100
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE WHEN t.IsModeratorOnly = 1 THEN 'Moderator Only' ELSE 'Public' END as TagType,
        CASE WHEN t.IsRequired = 1 THEN 'Required' ELSE 'Optional' END as TagRequirement,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as popularity_rank,
        LAG(t.Count) OVER (ORDER BY t.Count DESC) as prev_count,
        PERCENT_RANK() OVER (ORDER BY t.Count) as count_percentile
    FROM Tags t
    WHERE t.Count > 10
),
ComplexAnalysis AS (
    SELECT 
        rp.Id,
        rp.PostTypeId,
        rp.Score,
        rp.ViewCount,
        rp.Title,
        rp.Tags,
        rp.OwnerUserId,
        rp.CreationDate,
        rp.LastActivityDate,
        rp.AnswerCount,
        rp.CommentCount,
        rp.FavoriteCount,
        rp.score_rank,
        rp.score_percentile,
        COALESCE(rp.prev_score, 0) as prev_score,
        COALESCE(rp.prev_views, 0) as prev_views,
        CASE WHEN rp.Score > COALESCE(rp.prev_score, 0) THEN 'Improving' 
             WHEN rp.Score < COALESCE(rp.prev_score, 0) THEN 'Declining' 
             ELSE 'Stable' END as ScoreTrend,
        CASE WHEN rp.ViewCount > COALESCE(rp.prev_views, 0) THEN 'More Views' 
             WHEN rp.ViewCount < COALESCE(rp.prev_views, 0) THEN 'Fewer Views' 
             ELSE 'Same Views' END as ViewTrend,
        DATEDIFF('DAY', rp.CreationDate, rp.LastActivityDate) as DaysSinceLastActivity,
        CASE WHEN DATEDIFF('DAY', rp.CreationDate, rp.LastActivityDate) > 30 THEN 'Inactive' 
             WHEN DATEDIFF('DAY', rp.CreationDate, rp.LastActivityDate) > 7 THEN 'Semi-Active' 
             ELSE 'Active' END as ActivityLevel,
        CASE WHEN rp.AnswerCount > 1 THEN 'Has Answers' ELSE 'No Answers' END as AnswerStatus
    FROM RankedPosts rp
    WHERE rp.rn = 1
),
CombinedResults AS (
    SELECT 
        ca.Id,
        ca.PostTypeId,
        ca.Score,
        ca.ViewCount,
        ca.Title,
        ca.Tags,
        ca.OwnerUserId,
        ca.CreationDate,
        ca.LastActivityDate,
        ca.AnswerCount,
        ca.CommentCount,
        ca.FavoriteCount,
        ca.score_rank,
        ca.score_percentile,
        ca.prev_score,
        ca.prev_views,
        ca.ScoreTrend,
        ca.ViewTrend,
        ca.DaysSinceLastActivity,
        ca.ActivityLevel,
        ca.AnswerStatus,
        ua.DisplayName,
        ua.Reputation,
        ua.Views as UserViews,
        ua.PostCount,
        ua.CommentCount as UserCommentCount,
        ua.BadgeCount,
        ua.AvgPostScore,
        ua.ActivityStatus,
        ta.TagName,
        ta.TagCount,
        ta.TagType,
        ta.TagRequirement,
        ta.popularity_rank,
        ta.count_percentile,
        CASE WHEN ta.TagCount > (SELECT AVG(TagCount) FROM TagAnalysis) THEN 'Above Average' ELSE 'Below Average' END as TagPerformance,
        CASE WHEN ca.Score > (SELECT AVG(Score) FROM ComplexAnalysis) THEN 'Above Average' ELSE 'Below Average' END as PostPerformance,
        CASE WHEN ca.ViewCount > (SELECT AVG(ViewCount) FROM ComplexAnalysis) THEN 'High Views' ELSE 'Low Views' END as ViewPerformance,
        CASE WHEN ca.AnswerCount > (SELECT AVG(AnswerCount) FROM ComplexAnalysis) THEN 'Many Answers' ELSE 'Few Answers' END as AnswerPerformance
    FROM ComplexAnalysis ca
    LEFT JOIN UserActivity ua ON ca.OwnerUserId = ua.UserId
    LEFT JOIN (
        SELECT DISTINCT 
            p.Id,
            t.TagName,
            t.Count as TagCount,
            t.IsModeratorOnly,
            t.IsRequired
        FROM Posts p
        JOIN unnest(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')) as tag_array ON TRUE
        JOIN Tags t ON t.TagName = tag_array
        WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
    ) ta ON ca.Id = ta.Id
    WHERE ca.PostTypeId IN (1, 2)
)
SELECT 
    cr.Id as PostId,
    cr.PostTypeId,
    cr.Score,
    cr.ViewCount,
    cr.Title,
    cr.Tags,
    cr.OwnerUserId,
    cr.CreationDate,
    cr.LastActivityDate,
    cr.AnswerCount,
    cr.CommentCount,
    cr.FavoriteCount,
    cr.score_rank,
    cr.score_percentile,
    cr.prev_score,
    cr.prev_views,
    cr.ScoreTrend,
    cr.ViewTrend,
    cr.DaysSinceLastActivity,
    cr.ActivityLevel,
    cr.AnswerStatus,
    cr.DisplayName,
    cr.Reputation,
    cr.UserViews,
    cr.PostCount,
    cr.UserCommentCount,
    cr.BadgeCount,
    cr.AvgPostScore,
    cr.ActivityStatus,
    cr.TagName,
    cr.TagCount,
    cr.TagType,
    cr.TagRequirement,
    cr.popularity_rank,
    cr.count_percentile,
    cr.TagPerformance,
    cr.PostPerformance,
    cr.ViewPerformance,
    cr.AnswerPerformance,
    CASE 
        WHEN ABS(cr.score_rank - cr.popularity_rank) <= 5 THEN 'Similar Rankings'
        WHEN cr.score_rank > cr.popularity_rank THEN 'High Score, Low Popularity'
        ELSE 'High Popularity, Low Score'
    END as RankingComparison,
    CASE 
        WHEN cr.Score > 100 AND cr.ViewCount > 1000 THEN 'High Impact'
        WHEN cr.Score > 50 AND cr.ViewCount > 500 THEN 'Medium Impact'
        WHEN cr.Score > 10 AND cr.ViewCount > 100 THEN 'Low Impact'
        ELSE 'Minimal Impact'
    END as ImpactLevel,
    RANK() OVER (ORDER BY cr.Score DESC, cr.ViewCount DESC) as OverallRank,
    ROW_NUMBER() OVER (ORDER BY cr.Score DESC) as ScoreRank,
    DENSE_RANK() OVER (ORDER BY cr.ViewCount DESC) as ViewRank
FROM CombinedResults cr
WHERE cr.Reputation > 500
    AND cr.PostCount > 10
    AND (cr.ActivityStatus = 'Active' OR cr.ActivityLevel = 'Active')
    AND cr.AnswerStatus = 'Has Answers'
    AND cr.ScoreTrend IN ('Improving', 'Stable')
    AND cr.ViewTrend IN ('More Views', 'Same Views')
    AND cr.DaysSinceLastActivity <= 90
    AND cr.TagCount >= 5
    AND cr.TagPerformance = 'Above Average'
    AND cr.PostPerformance = 'Above Average'
    AND cr.ViewPerformance = 'High Views'
ORDER BY 
    cr.Score DESC,
    cr.ViewCount DESC,
    cr.Reputation DESC,
    cr.PostCount DESC,
    cr.AvgPostScore DESC,
    cr.TagCount DESC
LIMIT 1000;
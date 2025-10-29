-- {"query": "7822.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1851} 
WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as UserPostRank,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) as ScoreRank,
        LAG(p.Score) OVER (ORDER BY p.CreationDate) as PrevScore,
        LEAD(p.Score) OVER (ORDER BY p.CreationDate) as NextScore,
        AVG(p.Score) OVER (PARTITION BY p.PostTypeId) as AvgScoreByType,
        CASE 
            WHEN p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = p.PostTypeId) THEN 'AboveAvg'
            WHEN p.Score < (SELECT AVG(Score) FROM Posts WHERE PostTypeId = p.PostTypeId) THEN 'BelowAvg'
            ELSE 'Avg'
        END as ScoreCategory,
        COALESCE(p.Title, '') + ' - ' + COALESCE(p.Tags, '') as TitleTagConcat
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) 
      AND p.CreationDate >= DATEADD(YEAR, -2, GETDATE())
),
UserActivity AS (
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
            WHEN COUNT(DISTINCT p.Id) > 100 THEN 'High'
            WHEN COUNT(DISTINCT p.Id) > 50 THEN 'Medium'
            ELSE 'Low'
        END as ActivityLevel
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= DATEADD(YEAR, -5, GETDATE())
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > (SELECT AVG(Count) FROM Tags) THEN 'Popular'
            WHEN t.Count < (SELECT AVG(Count) FROM Tags) THEN 'Rare'
            ELSE 'Average'
        END as PopularityLevel,
        DENSE_RANK() OVER (ORDER BY t.Count DESC) as PopularityRank
    FROM Tags t
),
ComplexPostAnalysis AS (
    SELECT 
        rp.Id,
        rp.TitleTagConcat,
        rp.Score,
        rp.ViewCount,
        rp.AnswerCount,
        rp.CommentCount,
        rp.FavoriteCount,
        rp.UserPostRank,
        rp.ScoreRank,
        rp.ScoreCategory,
        rp.AvgScoreByType,
        CASE 
            WHEN rp.Score > rp.AvgScoreByType AND rp.Score > 50 THEN 'HighPerforming'
            WHEN rp.Score < rp.AvgScoreByType AND rp.Score < 10 THEN 'LowPerforming'
            WHEN rp.Score BETWEEN rp.AvgScoreByType - 10 AND rp.AvgScoreByType + 10 THEN 'Moderate'
            ELSE 'Unusual'
        END as PerformanceLevel,
        CASE 
            WHEN rp.AnswerCount > 0 AND rp.CommentCount > 0 THEN 'Active'
            WHEN rp.AnswerCount = 0 AND rp.CommentCount > 0 THEN 'Commented'
            WHEN rp.AnswerCount > 0 AND rp.CommentCount = 0 THEN 'Answered'
            ELSE 'Inactive'
        END as EngagementStatus,
        rp.PrevScore,
        rp.NextScore,
        ISNULL(rp.PrevScore, 0) - ISNULL(rp.NextScore, 0) as ScoreChangeFromPrevNext,
        CONCAT('Tag-', rp.Tags) as TagPrefix,
        RIGHT(rp.Tags, 20) as TagSuffix,
        LEN(rp.TitleTagConcat) as TitleTagLength,
        CASE 
            WHEN rp.Tags LIKE '%<%' THEN 'HasTags'
            ELSE 'NoTags'
        END as TagStatus,
        ROW_NUMBER() OVER (ORDER BY rp.Score DESC, rp.ViewCount DESC) as OverallRanking,
        DENSE_RANK() OVER (PARTITION BY rp.PostTypeId ORDER BY rp.Score DESC) as TypeSpecificRank
    FROM RankedPosts rp
),
FinalCombined AS (
    SELECT 
        cpa.Id,
        cpa.TitleTagConcat,
        cpa.Score,
        cpa.ViewCount,
        cpa.AnswerCount,
        cpa.CommentCount,
        cpa.FavoriteCount,
        cpa.UserPostRank,
        cpa.ScoreRank,
        cpa.PerformanceLevel,
        cpa.EngagementStatus,
        cpa.TagPrefix,
        cpa.TagSuffix,
        cpa.TitleTagLength,
        CASE 
            WHEN cpa.ScoreChangeFromPrevNext > 10 THEN 'Rising'
            WHEN cpa.ScoreChangeFromPrevNext < -10 THEN 'Falling'
            ELSE 'Stable'
        END as Trend,
        ISNULL(ua.DisplayName, 'Unknown') as AuthorName,
        ISNULL(ua.Reputation, 0) as AuthorReputation,
        ISNULL(ua.PostCount, 0) as AuthorPostCount,
        ISNULL(ta.TagName, 'NoTag') as AssociatedTag,
        ISNULL(ta.PopularityLevel, 'Unknown') as TagPopularity,
        CASE 
            WHEN ISNULL(ua.PostCount, 0) > 100 AND ISNULL(ua.Reputation, 0) > 1000 THEN 'Elite'
            WHEN ISNULL(ua.PostCount, 0) > 50 AND ISNULL(ua.Reputation, 0) > 500 THEN 'Experienced'
            WHEN ISNULL(ua.PostCount, 0) > 0 AND ISNULL(ua.Reputation, 0) > 0 THEN 'Active'
            ELSE 'New'
        END as AuthorMaturity,
        CASE 
            WHEN cpa.Score > 0 AND cpa.ViewCount > 0 THEN CAST(cpa.Score AS FLOAT) / CAST(cpa.ViewCount AS FLOAT)
            ELSE 0.0
        END as ScoreToViewRatio
    FROM ComplexPostAnalysis cpa
    LEFT JOIN UserActivity ua ON cpa.Id IN (SELECT Id FROM Posts WHERE OwnerUserId = ua.UserId)
    LEFT JOIN Tags ta ON cpa.TagSuffix LIKE '%' + ta.TagName + '%'
)
SELECT 
    fc.Id,
    fc.TitleTagConcat,
    fc.Score,
    fc.ViewCount,
    fc.AnswerCount,
    fc.CommentCount,
    fc.FavoriteCount,
    fc.UserPostRank,
    fc.ScoreRank,
    fc.PerformanceLevel,
    fc.EngagementStatus,
    fc.TagPrefix,
    fc.TagSuffix,
    fc.TitleTagLength,
    fc.Trend,
    fc.AuthorName,
    fc.AuthorReputation,
    fc.AuthorPostCount,
    fc.AssociatedTag,
    fc.TagPopularity,
    fc.AuthorMaturity,
    fc.ScoreToViewRatio,
    CASE 
        WHEN fc.ScoreToViewRatio > 0.1 THEN 'HighlyEngaged'
        WHEN fc.ScoreToViewRatio > 0.05 THEN 'ModeratelyEngaged'
        WHEN fc.ScoreToViewRatio > 0 THEN 'LowEngagement'
        ELSE 'NoEngagement'
    END as EngagementLevel,
    CASE 
        WHEN fc.Score > (SELECT AVG(Score) FROM Posts) * 1.5 THEN 'Extreme'
        WHEN fc.Score >= (SELECT AVG(Score) FROM Posts) * 1.2 THEN 'High'
        WHEN fc.Score >= (SELECT AVG(Score) FROM Posts) THEN 'Standard'
        WHEN fc.Score >= (SELECT AVG(Score) FROM Posts) * 0.8 THEN 'Low'
        ELSE 'VeryLow'
    END as ScoreTier,
    DENSE_RANK() OVER (ORDER BY fc.ScoreToViewRatio DESC) as EngagementRank,
    PERCENT_RANK() OVER (ORDER BY fc.Score) as ScorePercentile,
    NTILE(10) OVER (ORDER BY fc.Score) as ScoreDecile
FROM FinalCombined fc
WHERE fc.Id IS NOT NULL
ORDER BY fc.Score DESC, fc.ViewCount DESC
OPTION (MAXDOP 8, RECOMPILE);
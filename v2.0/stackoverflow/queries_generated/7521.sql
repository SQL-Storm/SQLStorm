-- {"query": "7521.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2612} 
WITH RECURSIVE PostHierarchy AS (
    SELECT 
        p.Id as PostId,
        p.ParentId,
        p.PostTypeId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        0 as Level,
        CAST(p.Id AS VARCHAR(1000)) as Path
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.ParentId IS NULL
    
    UNION ALL
    
    SELECT 
        p.Id as PostId,
        p.ParentId,
        p.PostTypeId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        ph.Level + 1,
        ph.Path || '->' || CAST(p.Id AS VARCHAR)
    FROM Posts p
    INNER JOIN PostHierarchy ph ON p.ParentId = ph.PostId
    WHERE ph.Level < 3
),
UserStats AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.DisplayName,
        u.CreationDate,
        u.Views,
        COUNT(DISTINCT b.Id) as BadgeCount,
        COUNT(DISTINCT p.Id) as PostCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) as QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) as AnswerCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) as TotalQuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) as TotalAnswerScore,
        MAX(p.CreationDate) as LastPostDate,
        AVG(p.Score) as AveragePostScore,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') as AllTags
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Id > 0
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.CreationDate, u.Views
),
PostAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.LastEditDate,
        p.LastActivityDate,
        p.CommentCount,
        p.AnswerCount,
        COALESCE(p.FavoriteCount, 0) as FavoriteCount,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END as IsClosed,
        CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END as IsCommunityOwned,
        CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END as HasAcceptedAnswer,
        DATEDIFF(day, p.CreationDate, COALESCE(p.ClosedDate, p.LastActivityDate)) as DaysSinceCreation,
        DATEDIFF(day, p.CreationDate, p.LastEditDate) as DaysSinceLastEdit,
        CASE 
            WHEN p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2 THEN 
                ARRAY_LENGTH(SPLIT_PART(p.Tags, '><', ', '), ', ')
            ELSE 0 
        END as TagCount,
        LENGTH(p.Body) as BodyLength,
        CASE 
            WHEN p.Score > 100 THEN 'High'
            WHEN p.Score > 50 THEN 'Medium'
            WHEN p.Score > 0 THEN 'Low'
            ELSE 'Zero'
        END as ScoreCategory,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) as ScoreRank,
        RANK() OVER (ORDER BY p.Score DESC) as OverallScoreRank,
        PERCENT_RANK() OVER (ORDER BY p.Score) as ScorePercentile,
        NTILE(10) OVER (ORDER BY p.Score) as ScoreDecile
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) AND p.Score IS NOT NULL
),
CommentAnalysis AS (
    SELECT 
        c.PostId,
        COUNT(*) as CommentCount,
        SUM(c.Score) as TotalCommentScore,
        AVG(c.Score) as AverageCommentScore,
        MAX(c.CreationDate) as LatestCommentDate,
        STRING_AGG(SUBSTRING(c.Text, 1, 50), ' | ') as CommentSnippets
    FROM Comments c
    GROUP BY c.PostId
),
ComplexMetrics AS (
    SELECT 
        pa.PostId,
        pa.Title,
        pa.Score,
        pa.ViewCount,
        pa.OwnerUserId,
        pa.CreationDate,
        pa.IsClosed,
        pa.HasAcceptedAnswer,
        pa.DaysSinceCreation,
        pa.TagCount,
        pa.BodyLength,
        pa.ScoreCategory,
        pa.ScoreRank,
        pa.OverallScoreRank,
        pa.ScorePercentile,
        pa.ScoreDecile,
        COALESCE(ca.CommentCount, 0) as CommentCount,
        COALESCE(ca.TotalCommentScore, 0) as TotalCommentScore,
        COALESCE(ca.AverageCommentScore, 0) as AverageCommentScore,
        CASE 
            WHEN pa.Score > 0 AND ca.TotalCommentScore > 0 THEN 
                (pa.Score * 1.0 / NULLIF(ca.TotalCommentScore, 0))
            ELSE 0 
        END as ScoreToCommentRatio,
        CASE 
            WHEN pa.ViewCount > 0 AND pa.Score > 0 THEN 
                (pa.ViewCount * 1.0 / NULLIF(pa.Score, 0))
            ELSE 0 
        END as ViewsPerScore,
        CASE 
            WHEN pa.CommentCount > 0 AND pa.Score > 0 THEN 
                (pa.CommentCount * 1.0 / NULLIF(pa.Score, 0))
            ELSE 0 
        END as CommentsPerScore,
        CASE 
            WHEN pa.DaysSinceCreation > 0 AND pa.Score > 0 THEN 
                (pa.Score * 1.0 / NULLIF(pa.DaysSinceCreation, 0))
            ELSE 0 
        END as ScorePerDay,
        CASE 
            WHEN pa.ViewCount > 0 AND pa.DaysSinceCreation > 0 THEN 
                (pa.ViewCount * 1.0 / NULLIF(pa.DaysSinceCreation, 0))
            ELSE 0 
        END as ViewsPerDay,
        CASE 
            WHEN pa.TagCount > 0 AND pa.Score > 0 THEN 
                (pa.TagCount * 1.0 / NULLIF(pa.Score, 0))
            ELSE 0 
        END as TagsPerScore,
        NULLIF(pa.Score / NULLIF(pa.ViewCount, 0), 0) as ScoreRatio,
        CASE 
            WHEN pa.TagCount > 0 AND pa.CommentCount > 0 THEN 
                (pa.TagCount * 1.0 / NULLIF(pa.CommentCount, 0))
            ELSE 0 
        END as TagsPerComment
    FROM PostAnalysis pa
    LEFT JOIN CommentAnalysis ca ON pa.PostId = ca.PostId
)
SELECT 
    cm.PostId,
    cm.Title,
    cm.Score,
    cm.ViewCount,
    cm.OwnerUserId,
    cm.CreationDate,
    cm.IsClosed,
    cm.HasAcceptedAnswer,
    cm.DaysSinceCreation,
    cm.TagCount,
    cm.BodyLength,
    cm.ScoreCategory,
    cm.ScoreRank,
    cm.OverallScoreRank,
    cm.ScorePercentile,
    cm.ScoreDecile,
    cm.CommentCount,
    cm.TotalCommentScore,
    cm.AverageCommentScore,
    cm.ScoreToCommentRatio,
    cm.ViewsPerScore,
    cm.CommentsPerScore,
    cm.ScorePerDay,
    cm.ViewsPerDay,
    cm.TagsPerScore,
    cm.ScoreRatio,
    cm.TagsPerComment,
    us.Reputation,
    us.DisplayName as OwnerDisplayName,
    us.PostCount,
    us.QuestionCount,
    us.AnswerCount,
    us.TotalQuestionScore,
    us.TotalAnswerScore,
    us.AveragePostScore,
    us.BadgeCount,
    CASE 
        WHEN cm.Score > 200 THEN 'Elite'
        WHEN cm.Score > 100 THEN 'High'
        WHEN cm.Score > 50 THEN 'Medium'
        WHEN cm.Score > 0 THEN 'Low'
        ELSE 'Zero'
    END as PerformanceTier,
    CASE 
        WHEN cm.CommentCount > 10 AND cm.Score > 100 THEN 'Engaged'
        WHEN cm.CommentCount > 0 AND cm.Score > 50 THEN 'Active'
        WHEN cm.Score > 0 THEN 'Minimal'
        ELSE 'Inactive'
    END as EngagementLevel,
    CASE 
        WHEN cm.DaysSinceCreation BETWEEN 0 AND 30 THEN 'New'
        WHEN cm.DaysSinceCreation BETWEEN 31 AND 365 THEN 'Established'
        WHEN cm.DaysSinceCreation > 365 THEN 'Veteran'
        ELSE 'Unknown'
    END as AgeCategory,
    LAG(cm.Score, 1) OVER (ORDER BY cm.Score DESC) as PreviousScore,
    LEAD(cm.Score, 1) OVER (ORDER BY cm.Score DESC) as NextScore,
    AVG(cm.Score) OVER (ORDER BY cm.Score DESC ROWS BETWEEN 5 PRECEDING AND 5 FOLLOWING) as ScoreMovingAverage,
    COUNT(*) OVER () as TotalPosts,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY cm.Score) as MedianScore,
    COUNT(*) OVER (PARTITION BY cm.ScoreCategory) as PostsInCategory,
    MAX(cm.TagCount) OVER (PARTITION BY cm.PostId) as MaxTagsInPost,
    ROW_NUMBER() OVER (ORDER BY cm.Score DESC, cm.CommentCount DESC) as RankByScoreAndComments,
    DENSE_RANK() OVER (ORDER BY cm.Score DESC) as DenseScoreRank,
    RANK() OVER (ORDER BY cm.Score DESC, cm.ViewCount DESC) as CompositeRank,
    CASE 
        WHEN cm.ScorePercentile >= 0.95 THEN 'Top 5%'
        WHEN cm.ScorePercentile >= 0.75 THEN 'Top 25%'
        WHEN cm.ScorePercentile >= 0.5 THEN 'Top 50%'
        WHEN cm.ScorePercentile >= 0.25 THEN 'Bottom 75%'
        ELSE 'Bottom 25%'
    END as PercentileGroup,
    CASE 
        WHEN cm.ScoreCategory IN ('High', 'Medium') AND cm.CommentsPerScore > 0.1 THEN 
            'Well Discussable'
        WHEN cm.ScoreCategory = 'High' AND cm.CommentsPerScore <= 0.1 THEN 
            'High Score, Low Engagement'
        WHEN cm.ScoreCategory = 'Low' AND cm.CommentsPerScore > 0.05 THEN 
            'Low Score, High Engagement'
        ELSE 
            'Average'
    END as ContentImpact,
    CASE 
        WHEN cm.Score > 10 AND cm.TagCount > 0 AND cm.TagCount <= 5 THEN 
            'Optimal Tagging'
        WHEN cm.TagCount > 5 THEN 
            'Over Tagged'
        WHEN cm.TagCount = 0 THEN 
            'Untagged'
        ELSE 
            'Normal'
    END as TaggingEfficiency,
    CASE 
        WHEN cm.ScorePerDay > 0.1 AND cm.ViewsPerDay > 0.5 THEN 'High Velocity'
        WHEN cm.ScorePerDay > 0.05 AND cm.ViewsPerDay > 0.25 THEN 'Moderate Velocity'
        WHEN cm.ScorePerDay > 0 THEN 'Low Velocity'
        ELSE 'No Velocity'
    END as PerformanceVelocity
FROM ComplexMetrics cm
LEFT JOIN UserStats us ON cm.OwnerUserId = us.UserId
WHERE cm.Score > 0 
    AND cm.TagCount BETWEEN 1 AND 10
    AND cm.DaysSinceCreation > 0
    AND cm.BodyLength > 50
    AND cm.CommentCount >= 0
    AND (us.PostCount > 0 OR us.PostCount IS NULL)
    AND cm.Title IS NOT NULL
    AND cm.Title != ''
    AND cm.Title LIKE '%%'
ORDER BY 
    cm.Score DESC,
    cm.CommentCount DESC,
    cm.ViewCount DESC
LIMIT 100000 OFFSET 0;
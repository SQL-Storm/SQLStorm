-- {"query": "7901.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2470} 
WITH PostMetrics AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.Body,
        COALESCE(p.ParentId, p.Id) as PostGroupId,
        DENSE_RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as UserPostRank,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate) as GlobalPostNumber,
        LAG(p.CreationDate) OVER (ORDER BY p.CreationDate) as PreviousPostDate,
        LEAD(p.CreationDate) OVER (ORDER BY p.CreationDate) as NextPostDate,
        NTILE(100) OVER (ORDER BY p.Score) as ScorePercentile,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AnswerCount = 0 THEN 'Unanswered Question'
            WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN 'Answered Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostCategory,
        CASE 
            WHEN p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2 THEN 
                ARRAY_LENGTH(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'), 1)
            ELSE 0 
        END as TagCount
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) AND p.CreationDate >= '2010-01-01'
),
UserActivity AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.DisplayName,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.AccountId,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        COUNT(DISTINCT c.Id) as Comments,
        SUM(p.Score) as TotalScore,
        AVG(p.Score) as AvgScore,
        MAX(p.CreationDate) as LastPostDate,
        MIN(p.CreationDate) as FirstPostDate,
        DATEDIFF('day', MIN(p.CreationDate), MAX(p.CreationDate)) as ActiveDays,
        IIF(SUM(p.Score) > 0, SUM(p.Score) * 100.0 / NULLIF(AVG(p.Score) * COUNT(p.Id), 0), 0) as ScoreEfficiency
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    WHERE u.CreationDate >= '2010-01-01'
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes, u.AccountId
),
TagAnalytics AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId as ExcerptPostId,
        t.WikiPostId as WikiPostId,
        COALESCE(p1.ViewCount, 0) as ExcerptViews,
        COALESCE(p2.ViewCount, 0) as WikiViews,
        IIF(t.Count > 0, 
            CAST((COALESCE(p1.ViewCount, 0) + COALESCE(p2.ViewCount, 0)) * 100.0 / NULLIF(t.Count, 0) AS DECIMAL(10,2)), 0) as ViewsPerTagUse,
        CASE 
            WHEN t.Count > 1000 THEN 'High Usage'
            WHEN t.Count > 100 THEN 'Medium Usage'
            WHEN t.Count > 10 THEN 'Low Usage'
            ELSE 'Very Low Usage'
        END as UsageLevel
    FROM Tags t
    LEFT JOIN Posts p1 ON t.ExcerptPostId = p1.Id
    LEFT JOIN Posts p2 ON t.WikiPostId = p2.Id
),
PerformanceAnalysis AS (
    SELECT 
        pm.Id,
        pm.PostTypeId,
        pm.OwnerUserId,
        pm.Score,
        pm.ViewCount,
        pm.AnswerCount,
        pm.CommentCount,
        pm.FavoriteCount,
        pm.Title,
        pm.Tags,
        pm.PostCategory,
        pm.TagCount,
        pm.ScorePercentile,
        pm.UserPostRank,
        pm.GlobalPostNumber,
        CASE 
            WHEN pm.Score > 100 THEN 'Highly Upvoted'
            WHEN pm.Score > 10 THEN 'Moderately Upvoted'
            WHEN pm.Score > 0 THEN 'Slightly Upvoted'
            ELSE 'Not Upvoted'
        END as UpvoteStatus,
        pm.CreationDate,
        CASE 
            WHEN pm.PreviousPostDate IS NOT NULL 
                AND DATEDIFF('hour', pm.PreviousPostDate, pm.CreationDate) < 1 
                THEN 'Rapid Fire'
            WHEN DATEDIFF('day', pm.CreationDate, CURRENT_TIMESTAMP()) > 365 
                THEN 'Stale'
            WHEN pm.PostTypeId = 1 AND pm.AnswerCount > 10 
                THEN 'Highly Engaged'
            ELSE 'Regular'
        END as ActivityLevel,
        COALESCE(ua.TotalPosts, 0) as UserTotalPosts,
        COALESCE(ua.Questions, 0) as UserQuestions,
        COALESCE(ua.Answers, 0) as UserAnswers,
        COALESCE(ua.ScoreEfficiency, 0) as UserScoreEfficiency,
        COALESCE(ta.TagCount, 0) as TagReferenceCount,
        COALESCE(COUNT(b.Id), 0) as BadgeCount,
        IIF(pm.ViewCount > 0 AND pm.Score > 0, 
            CAST(pm.ViewCount * 100.0 / NULLIF(pm.Score, 0) AS DECIMAL(10,2)), 0) as ViewScoreRatio,
        IIF(pm.Score > 0 AND pm.AnswerCount > 0, 
            CAST(pm.AnswerCount * 100.0 / NULLIF(pm.Score, 0) AS DECIMAL(10,2)), 0) as AnswerScoreRatio,
        COALESCE(pm.NextPostDate, '2020-01-01') - pm.CreationDate as TimeToNextPost,
        IIF(pm.ViewCount >= 1000, 'Viral', 
            IIF(pm.ViewCount >= 100, 'Popular', 'Normal')) as ViewStatus
    FROM PostMetrics pm
    LEFT JOIN UserActivity ua ON pm.OwnerUserId = ua.UserId
    LEFT JOIN TagAnalytics ta ON pm.Tags IS NOT NULL AND CHARINDEX('<' + ta.TagName + '>', pm.Tags) > 0
    LEFT JOIN Badges b ON pm.OwnerUserId = b.UserId
    WHERE pm.PostTypeId IN (1, 2)
),
CombinedAnalysis AS (
    SELECT 
        pa.*,
        ROW_NUMBER() OVER (ORDER BY pa.ViewScoreRatio DESC) as ViewScoreRatioRank,
        RANK() OVER (ORDER BY pa.TagCount DESC) as TagCountRank,
        DENSE_RANK() OVER (ORDER BY pa.UserTotalPosts DESC) as UserPostRanking,
        PERCENT_RANK() OVER (ORDER BY pa.Score) as ScorePercentile,
        IIF(pa.UserTotalPosts > 1000 AND pa.UserScoreEfficiency > 50, 
            'Elite Contributor', 
            IIF(pa.UserTotalPosts > 100 AND pa.UserScoreEfficiency > 30, 
                'Active Contributor', 
                'Regular Contributor')) as ContributorLevel,
        CASE 
            WHEN pa.Score > 1000 AND pa.ViewCount > 5000 THEN 'Viral High Performer'
            WHEN pa.Score > 500 AND pa.ViewCount > 2000 THEN 'High Performer'
            WHEN pa.Score > 100 AND pa.ViewCount > 500 THEN 'Medium Performer'
            WHEN pa.Score > 10 AND pa.ViewCount > 100 THEN 'Low Performer'
            ELSE 'New Contributor'
        END as PerformanceStatus,
        DATEDIFF('day', pa.CreationDate, CURRENT_TIMESTAMP()) as DaysSinceCreation,
        IIF(pa.Score >= 0 AND pa.AnswerCount > 0 AND pa.CommentCount > 0, 
            'Engaging Content', 'Passive Content') as EngagementLevel,
        COALESCE(pa.ViewStatus, 'Normal') as CurrentViewStatus,
        IIF(pa.AnswerCount > 0 AND pa.CommentCount > 0 AND pa.FavoriteCount > 0, 
            'High Engagement', 
            IIF(pa.AnswerCount > 0 OR pa.CommentCount > 0 OR pa.FavoriteCount > 0, 
                'Moderate Engagement', 'Low Engagement')) as EngagementCategory,
        IIF(pa.ScorePercentile >= 90 OR pa.AnswerCount >= 50, 
            'Top Tier', 'Standard') as PerformanceTier
    FROM PerformanceAnalysis pa
)
SELECT 
    ca.Id as PostId,
    ca.PostTypeId,
    ca.OwnerUserId,
    ca.Score,
    ca.ViewCount,
    ca.AnswerCount,
    ca.CommentCount,
    ca.FavoriteCount,
    ca.Title,
    ca.Tags,
    ca.PostCategory,
    ca.TagCount,
    ca.ScorePercentile,
    ca.UserPostRank,
    ca.GlobalPostNumber,
    ca.UpvoteStatus,
    ca.ActivityLevel,
    ca.UserTotalPosts,
    ca.UserQuestions,
    ca.UserAnswers,
    ca.UserScoreEfficiency,
    ca.ViewScoreRatio,
    ca.AnswerScoreRatio,
    ca.ViewScoreRatioRank,
    ca.TagCountRank,
    ca.UserPostRanking,
    ca.ContributorLevel,
    ca.PerformanceStatus,
    ca.DaysSinceCreation,
    ca.EngagementLevel,
    ca.ViewStatus,
    ca.EngagementCategory,
    ca.PerformanceTier,
    ca.CreationDate,
    'This post was created by user ' || ca.OwnerUserId || 
    ' (' || (SELECT DisplayName FROM Users WHERE Id = ca.OwnerUserId) || 
    ') and is categorized as a ' || ca.PostCategory || 
    '. It has received ' || ca.Score || ' upvotes and ' || ca.ViewCount || ' views. ' ||
    'The post has ' || ca.AnswerCount || ' answers, ' || ca.CommentCount || ' comments, and ' || ca.FavoriteCount || ' favorites. ' ||
    'The author has ' || ca.UserTotalPosts || ' total posts with a score efficiency of ' || ca.UserScoreEfficiency || '%.' as PostSummary
FROM CombinedAnalysis ca
WHERE ca.Id IS NOT NULL
    AND ca.UserTotalPosts >= 10
    AND ca.CreationDate BETWEEN '2010-01-01' AND '2020-12-31'
    AND ca.Score BETWEEN -10 AND 10000
    AND ca.ViewCount >= 0
    AND ca.AnswerCount >= 0
    AND ca.CommentCount >= 0
    AND ca.FavoriteCount >= 0
    AND (ca.TagCount > 0 OR ca.Tags IS NULL)
ORDER BY ca.ViewScoreRatio DESC, ca.DaysSinceCreation ASC
LIMIT 1000;
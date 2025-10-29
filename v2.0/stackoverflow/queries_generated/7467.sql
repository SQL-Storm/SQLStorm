-- {"query": "7467.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2836} 
WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as UserPostRank,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PrevScore,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as AvgScorePerUser,
        NTILE(10) OVER (ORDER BY p.Score DESC) as ScoreDecile,
        CASE 
            WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN 
                CASE WHEN LENGTH(p.Tags) > 50 THEN 'Long' ELSE 'Short' END
            ELSE 'No Tags'
        END as TagLengthCategory,
        IIF(p.PostTypeId = 1, p.AnswerCount, NULL) as QuestionAnswerCount,
        IIF(p.PostTypeId = 2, p.Score, NULL) as AnswerScore
    FROM Posts p
    WHERE p.CreationDate >= '2022-01-01'
),
UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.DisplayName,
        u.Views,
        COUNT(DISTINCT p.Id) as PostCount,
        SUM(p.Score) as TotalScore,
        AVG(p.Score) as AvgScore,
        MAX(p.CreationDate) as LastPostDate,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.AnswerCount ELSE 0 END), 0) as TotalAnswersToQuestions,
        IIF(COUNT(DISTINCT p.Id) > 0, 
            AVG(p.Score * 1.0) * 100 / NULLIF(MAX(p.Score) OVER(), 0), 
            NULL) as ScoreEfficiencyPercentage
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views
),
TopUsersByScore AS (
    SELECT 
        UserId,
        AVG(AvgScore) as AvgUserScore,
        SUM(PostCount) as TotalPosts,
        AVG(ScoreEfficiencyPercentage) as AvgEfficiency
    FROM UserActivityStats
    GROUP BY UserId
    HAVING AVG(AvgScore) > 100
),
ComplexTags AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            WHEN t.Count > 10 THEN 'Niche'
            ELSE 'Rare'
        END as PopularityLevel,
        IIF(t.IsRequired = 1, 'Required', 'Optional') as TagType,
        IIF(t.IsModeratorOnly = 1, 'Moderator Only', 'Public') as AccessLevel,
        COALESCE(
            (SELECT STRING_AGG(p.Title, ', ') 
             FROM Posts p 
             WHERE p.Tags LIKE '%' || t.TagName || '%' 
             AND p.PostTypeId = 1 
             AND p.CreationDate >= '2022-01-01'),
            'No Questions'
        ) as SampleQuestions
    FROM Tags t
    WHERE t.TagName IS NOT NULL AND t.TagName != ''
),
PostAnalysis AS (
    SELECT 
        rp.Id,
        rp.PostTypeId,
        rp.Score,
        rp.ViewCount,
        rp.CreationDate,
        rp.Title,
        rp.Tags,
        rp.AnswerCount,
        rp.CommentCount,
        rp.FavoriteCount,
        rp.ScoreDecile,
        rp.UserPostRank,
        IIF(rp.PrevScore IS NULL, 0, rp.Score - rp.PrevScore) as ScoreChange,
        rp.AvgScorePerUser,
        IIF(rp.Score > rp.AvgScorePerUser, 'Above Average', 'Below Average') as PerformanceCategory,
        CASE 
            WHEN rp.TagLengthCategory = 'Long' AND rp.Score > 50 THEN 'High Score Long Tagged Post'
            WHEN rp.TagLengthCategory = 'Short' AND rp.Score > 100 THEN 'High Score Short Tagged Post'
            WHEN rp.TagLengthCategory = 'No Tags' AND rp.Score > 20 THEN 'High Score Untagged Post'
            ELSE 'Others'
        END as PostClassification,
        IIF(rp.QuestionAnswerCount > 5, 'Highly Answered', 'Moderately Answered') as AnswerLevel,
        IIF(rp.AnswerCount IS NOT NULL AND rp.AnswerCount > 0, 
            CAST(rp.AnswerCount AS FLOAT) / NULLIF(rp.ViewCount, 0) * 100, 
            NULL) as AnswerToViewRatio,
        IIF(rp.CommentCount IS NOT NULL AND rp.CommentCount > 0, 
            CAST(rp.CommentCount AS FLOAT) / NULLIF(rp.ViewCount, 0) * 100, 
            NULL) as CommentToViewRatio,
        DATEDIFF(DAY, rp.CreationDate, CURRENT_TIMESTAMP) as DaysSinceCreation,
        IIF(DATEDIFF(DAY, rp.CreationDate, CURRENT_TIMESTAMP) > 30, 'Old', 'Recent') as PostAge,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.Id) as CommentCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = rp.Id AND v.VoteTypeId IN (2,3)) as VoteCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = rp.Id AND v.VoteTypeId = 5) as FavoriteCount,
        COALESCE(
            (SELECT STRING_AGG(CAST(v.UserId AS VARCHAR), ', ') 
             FROM Votes v 
             WHERE v.PostId = rp.Id AND v.VoteTypeId IN (2,3)), 
            'No Votes'
        ) as TopVoters,
        COALESCE(
            (SELECT STRING_AGG(c.Text, ' || ') 
             FROM Comments c 
             WHERE c.PostId = rp.Id 
             AND c.CreationDate >= '2022-01-01'), 
            'No Recent Comments'
        ) as RecentComments
        
    FROM RankedPosts rp
    WHERE rp.Score > 20
)
SELECT 
    pa.Id as PostId,
    pa.PostTypeId,
    pa.Score,
    pa.ViewCount,
    pa.CreationDate,
    pa.Title,
    pa.Tags,
    pa.AnswerCount,
    pa.CommentCount,
    pa.FavoriteCount,
    pa.ScoreDecile,
    pa.UserPostRank,
    pa.ScoreChange,
    pa.AvgScorePerUser,
    pa.PerformanceCategory,
    pa.PostClassification,
    pa.AnswerLevel,
    pa.AnswerToViewRatio,
    pa.CommentToViewRatio,
    pa.DaysSinceCreation,
    pa.PostAge,
    pa.CommentCount as ActualCommentCount,
    pa.VoteCount,
    pa.FavoriteCount as ActualFavoriteCount,
    pa.TopVoters,
    pa.RecentComments,
    CASE 
        WHEN pa.Score > 50 AND pa.ViewCount > 100 THEN 'High Impact'
        WHEN pa.Score > 20 AND pa.ViewCount > 50 THEN 'Moderate Impact'
        WHEN pa.Score > 10 AND pa.ViewCount > 20 THEN 'Low Impact'
        ELSE 'Minimal Impact'
    END as ImpactLevel,
    IIF(pa.FavoriteCount > 0 AND pa.Score > 100 AND pa.ViewCount > 200, 
        'High Engagement', 
        'Standard Engagement') as EngagementLevel,
    u.DisplayName as AuthorName,
    u.Reputation as AuthorReputation,
    u.Views as AuthorViews,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = u.Id AND p2.CreationDate >= '2022-01-01') as AuthorPostCount2022,
    (SELECT AVG(p2.Score) FROM Posts p2 WHERE p2.OwnerUserId = u.Id AND p2.CreationDate >= '2022-01-01') as AuthorAvgScore2022,
    cu.AvgUserScore as AuthorAvgUserScore,
    STRING_AGG(DISTINCT pa.Tags, ' | ') OVER() as AllTagsConcatenated,
    (SELECT STRING_AGG(tag.TagName, ', ') 
     FROM (
         SELECT TRIM(SUBSTRING(tag_list.value, 1, LENGTH(tag_list.value) - 1)) as TagName
         FROM STRING_SPLIT(REPLACE(REPLACE(pa.Tags, '<', ''), '>', ''), '<') as tag_list
         WHERE tag_list.value != ''
     ) tag
     WHERE tag.TagName IN (SELECT TagName FROM Tags WHERE Count > 100)
    ) as PopularTagNames,
    IIF(pa.PostAge = 'Recent' AND pa.Score > 5 AND pa.ViewCount > 5, 
        'Recently Active', 
        NULL) as ActivityIndicator,
    IIF(pa.AnswerCount > 10 AND pa.CommentCount > 5 AND pa.FavoriteCount > 10, 
        'High Engagement Post', 
        'Standard Post') as EngagementType,
    IIF(pa.Score > 100 AND pa.ViewCount > 200 AND pa.CommentCount > 10, 
        'Trending', 
        'Normal') as TrendStatus,
    IIF(pa.PostTypeId = 1 AND pa.AnswerCount IS NOT NULL AND pa.AnswerCount = 0, 
        'Unanswered Question', 
        'Answered Question') as QuestionStatus,
    IIF(pa.PostTypeId = 2 AND pa.Score > 100, 
        'High Quality Answer', 
        'Normal Answer') as AnswerQuality,
    IIF(pa.PostTypeId = 1 AND pa.Score > 50 AND pa.FavoriteCount > 5, 
        'Featured Question', 
        'Regular Question') as QuestionFeature,
    COALESCE(
        (SELECT STRING_AGG(CONCAT('User: ', u2.DisplayName, ' Reput: ', u2.Reputation), ' || ') 
         FROM Users u2 
         WHERE u2.Id IN (SELECT DISTINCT v.UserId FROM Votes v WHERE v.PostId = pa.Id)),
        'No Voters'
    ) as VoterProfiles,
    (SELECT MIN(b.Date) FROM Badges b WHERE b.UserId = u.Id) as FirstBadgeDate,
    COALESCE(
        (SELECT STRING_AGG(b.Name, ', ') 
         FROM Badges b 
         WHERE b.UserId = u.Id 
         AND b.Date >= '2022-01-01'),
        'No Recent Badges'
    ) as RecentBadges,
    IIF(pa.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = pa.PostTypeId), 
        'Above Forum Average', 
        'Below Forum Average') as ScoreComparison,
    IIF(pa.ViewCount > (SELECT AVG(ViewCount) FROM Posts WHERE PostTypeId = pa.PostTypeId), 
        'Above View Average', 
        'Below View Average') as ViewComparison,
    ABS(pa.Score - pa.AvgScorePerUser) as ScoreDeviationFromUserAvg,
    IIF(pa.Score > 0 AND pa.ViewCount > 0, 
        CAST(pa.Score AS FLOAT) / NULLIF(pa.ViewCount, 0), 
        NULL) as ScoreToViewRatio,
    IIF(pa.AnswerCount IS NOT NULL AND pa.AnswerCount > 0 AND pa.CommentCount IS NOT NULL, 
        CAST(pa.CommentCount AS FLOAT) / NULLIF(pa.AnswerCount, 0), 
        NULL) as CommentsPerAnswer,
    IIF(pa.AnswerCount IS NOT NULL AND pa.AnswerCount > 0 AND pa.FavoriteCount IS NOT NULL, 
        CAST(pa.FavoriteCount AS FLOAT) / NULLIF(pa.AnswerCount, 0), 
        NULL) as FavoritesPerAnswer,
    COALESCE(
        (SELECT STRING_AGG(CONCAT('Tag: ', t.TagName, ' Count:', t.Count), ' | ') 
         FROM Tags t 
         WHERE t.TagName IN (
             SELECT TRIM(tag.value) 
             FROM STRING_SPLIT(REPLACE(REPLACE(pa.Tags, '<', ''), '>', ''), '<') AS tag
             WHERE tag.value != ''
         )),
        'No Tag Info'
    ) as TagDetails,
    'Post-' || pa.Id || '-Analysis' as ReportIdentifier,
    CURRENT_TIMESTAMP as AnalysisTimestamp
FROM PostAnalysis pa
LEFT JOIN Users u ON pa.OwnerUserId = u.Id
LEFT JOIN TopUsersByScore cu ON pa.OwnerUserId = cu.UserId
WHERE pa.Score > 10
  AND u.Id IS NOT NULL
  AND pa.CreationDate >= '2022-01-01'
  AND pa.PostTypeId IN (1,2)
ORDER BY pa.Score DESC, pa.CreationDate DESC
LIMIT 1000 OFFSET 0;
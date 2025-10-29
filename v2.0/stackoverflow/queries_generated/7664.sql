-- {"query": "7664.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2019} 
WITH UserPostStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        SUM(COALESCE(p.Score, 0)) as TotalScore,
        AVG(COALESCE(p.Score, 0)) as AvgScore,
        MAX(p.CreationDate) as LastPostDate,
        STRING_AGG(DISTINCT p.Tags, ', ') as AllTags,
        COUNT(DISTINCT b.Id) as BadgesReceived,
        COUNT(DISTINCT c.Id) as CommentsMade
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    WHERE u.CreationDate >= '2010-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
RankedUsers AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (ORDER BY TotalScore DESC, Reputation DESC) as RankByScore,
        PERCENT_RANK() OVER (ORDER BY TotalScore) as ScorePercentile,
        NTILE(10) OVER (ORDER BY TotalScore) as ScoreDecile,
        LAG(DisplayName) OVER (ORDER BY TotalScore DESC) as PreviousTopUser,
        LEAD(DisplayName) OVER (ORDER BY TotalScore DESC) as NextTopUser
    FROM UserPostStats
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') as QuestionCount,
        (SELECT AVG(p.Score) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') as AvgScoreForTag,
        (SELECT STRING_AGG(DISTINCT u.DisplayName, ', ') 
         FROM Posts p 
         JOIN Users u ON p.OwnerUserId = u.Id 
         WHERE p.Tags LIKE '%' || t.TagName || '%') as TagUsers
    FROM Tags t
),
PostMetrics AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN 
                (SELECT COUNT(*) FROM Posts WHERE ParentId = p.Id AND PostTypeId = 2)
            ELSE 0 
        END as ActualAnswerCount,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AnswerCount IS NOT NULL AND p.AnswerCount > 0 THEN 
                CAST(p.AnswerCount AS FLOAT) / (COALESCE(p.AnswerCount, 0) + 1)
            ELSE 0 
        END as AnswerRatio,
        CASE 
            WHEN p.PostTypeId = 1 THEN 
                COALESCE((SELECT AVG(p2.Score) FROM Posts p2 WHERE p2.Tags LIKE '%' || p.Tags || '%' AND p2.PostTypeId = 1), 0)
            ELSE 0 
        END as TagAverageScore,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) as RankByScorePerType,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) as DenseScoreRank
    FROM Posts p
    WHERE p.CreationDate >= '2015-01-01' 
    AND p.Score IS NOT NULL
),
ComplexJoinResult AS (
    SELECT 
        ru.UserId,
        ru.DisplayName,
        ru.Reputation,
        ru.TotalPosts,
        ru.Questions,
        ru.Answers,
        ru.TotalScore,
        ru.AvgScore,
        ru.BadgesReceived,
        ru.CommentsMade,
        ta.TagName,
        ta.TagCount,
        ta.QuestionCount,
        ta.AvgScoreForTag,
        pm.Id as PostId,
        pm.Title,
        pm.Score as PostScore,
        pm.ViewCount,
        pm.CreationDate as PostCreationDate,
        pm.AnswerCount,
        pm.CommentCount,
        pm.FavoriteCount,
        pm.AnswerRatio,
        pm.TagAverageScore,
        pm.RankByScorePerType,
        pm.DenseScoreRank,
        CASE 
            WHEN ru.TotalScore > (SELECT AVG(TotalScore) FROM RankedUsers) THEN 'AboveAverage'
            WHEN ru.TotalScore > (SELECT AVG(TotalScore) * 0.75 FROM RankedUsers) THEN 'NearAverage'
            ELSE 'BelowAverage' 
        END as PerformanceLevel,
        CASE 
            WHEN pm.Score < 0 THEN 'NegativeScore'
            WHEN pm.Score BETWEEN 0 AND 1 THEN 'LowScore'
            WHEN pm.Score BETWEEN 2 AND 5 THEN 'MediumScore'
            WHEN pm.Score BETWEEN 6 AND 10 THEN 'HighScore'
            ELSE 'VeryHighScore'
        END as ScoreCategory,
        CASE 
            WHEN ru.RankByScore <= 10 THEN 'Top10'
            WHEN ru.RankByScore <= 100 THEN 'Top100'
            WHEN ru.RankByScore <= 1000 THEN 'Top1000'
            ELSE 'BeyondTop1000'
        END as RankCategory,
        COALESCE(ru.PreviousTopUser, 'None') as PreviousTopUser,
        COALESCE(ru.NextTopUser, 'None') as NextTopUser
    FROM RankedUsers ru
    INNER JOIN TagAnalysis ta ON ta.TagCount > 100 OR EXISTS (SELECT 1 FROM Posts WHERE OwnerUserId = ru.UserId AND Tags LIKE '%' || ta.TagName || '%')
    LEFT JOIN PostMetrics pm ON pm.OwnerUserId = ru.UserId AND pm.PostTypeId = 1
    WHERE ru.TotalPosts > 5
),
FinalAggregation AS (
    SELECT 
        COUNT(*) as TotalRecords,
        COUNT(DISTINCT UserId) as UniqueUsers,
        COUNT(DISTINCT PostId) as UniquePosts,
        COUNT(DISTINCT TagName) as UniqueTags,
        SUM(TotalScore) as OverallScoreSum,
        AVG(TotalScore) as AverageScorePerUser,
        MAX(OverallScoreSum) as MaxUserScoreSum,
        MIN(OverallScoreSum) as MinUserScoreSum,
        STRING_AGG(DISTINCT DisplayName, ' | ') as AllUserNames,
        STRING_AGG(COALESCE(PostId::text, 'N/A'), ' | ') as AllPostIds,
        STRING_AGG(COALESCE(TagName, 'N/A'), ' | ') as AllTagNames,
        STRING_AGG(CASE WHEN OverallScoreSum > 0 THEN 'Positive' ELSE 'NonPositive' END, ' | ') as ScoreStatuses
    FROM ComplexJoinResult
),
PostHistoryAnalysis AS (
    SELECT 
        ph.PostId,
        ph.PostHistoryTypeId,
        COUNT(*) as ChangeCount,
        MAX(ph.CreationDate) as LatestChange,
        MIN(ph.CreationDate) as FirstChange,
        DATEDIFF('day', MIN(ph.CreationDate), MAX(ph.CreationDate)) as DurationDays,
        COUNT(DISTINCT ph.UserId) as UniqueEditors
    FROM PostHistory ph
    WHERE ph.CreationDate >= '2016-01-01'
    GROUP BY ph.PostId, ph.PostHistoryTypeId
)
SELECT 
    fa.TotalRecords,
    fa.UniqueUsers,
    fa.UniquePosts,
    fa.UniqueTags,
    fa.OverallScoreSum,
    fa.AverageScorePerUser,
    fa.MaxUserScoreSum,
    fa.MinUserScoreSum,
    fa.AllUserNames,
    fa.AllPostIds,
    fa.AllTagNames,
    fa.ScoreStatuses,
    (
        SELECT STRING_AGG(
            CONCAT(
                'PostID:', pha.PostId, 
                '|Changes:', pha.ChangeCount, 
                '|Latest:', pha.LatestChange,
                '|First:', pha.FirstChange,
                '|DurationDays:', pha.DurationDays,
                '|Editors:', pha.UniqueEditors
            ), 
            '|'
        )
        FROM PostHistoryAnalysis pha
        WHERE pha.ChangeCount > 10
    ) as HighChangePostAnalysis
FROM FinalAggregation fa
WHERE EXISTS (
    SELECT 1 
    FROM ComplexJoinResult cjr 
    WHERE cjr.Reputation > 10000 
    AND cjr.ScoreCategory IN ('HighScore', 'VeryHighScore')
)
UNION ALL
SELECT 
    fa.TotalRecords,
    fa.UniqueUsers,
    fa.UniquePosts,
    fa.UniqueTags,
    0 as OverallScoreSum,
    0 as AverageScorePerUser,
    0 as MaxUserScoreSum,
    0 as MinUserScoreSum,
    'NULL_USER_NAMES' as AllUserNames,
    'NULL_POST_IDS' as AllPostIds,
    'NULL_TAG_NAMES' as AllTagNames,
    'NULL_SCORE_STATUSES' as ScoreStatuses
FROM FinalAggregation fa
WHERE NOT EXISTS (
    SELECT 1 
    FROM ComplexJoinResult cjr 
    WHERE cjr.Answers > 5 AND cjr.CommentsMade > 20
)
ORDER BY TotalRecords DESC
LIMIT 100;
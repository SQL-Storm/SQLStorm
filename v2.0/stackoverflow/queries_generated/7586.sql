-- {"query": "7586.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2127} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        COUNT(DISTINCT c.Id) as Comments,
        COUNT(DISTINCT b.Id) as Badges,
        MAX(p.CreationDate) as LastPostDate,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 0 THEN 
                ROUND(CAST(SUM(p.Score) AS FLOAT) / COUNT(DISTINCT p.Id), 2)
            ELSE 0 
        END as AvgScorePerPost,
        STRING_AGG(DISTINCT LEFT(p.Tags, 20), ', ') as TagSummary
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2010-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopUsers AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (ORDER BY TotalScore DESC, Reputation DESC) as RankScore,
        DENSE_RANK() OVER (ORDER BY TotalPosts DESC) as RankPosts,
        NTILE(10) OVER (ORDER BY Reputation DESC) as ReputationQuantile
    FROM UserActivityStats
),
PostAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Body,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.AnswerCount,
        p.CommentCount,
        p.Tags,
        p.ParentId,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END as PostTypeDesc,
        IIF(p.Score > 0, 
            CONCAT('High ', CASE WHEN p.PostTypeId = 1 THEN 'Question' ELSE 'Answer' END),
            CONCAT('Low ', CASE WHEN p.PostTypeId = 1 THEN 'Question' ELSE 'Answer' END)
        ) as ScoreCategory,
        COALESCE(
            (SELECT COUNT(*) FROM Posts WHERE ParentId = p.Id AND PostTypeId = 2 AND Score > 0),
            0
        ) as HighScoreAnswers,
        LAG(p.CreationDate, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PreviousPostDate,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PreviousScore,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC) as ScoreRank,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as UserAvgScore,
        CASE 
            WHEN p.Tags IS NOT NULL AND LENGTH(p.Tags) > 3 
            THEN STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')
            ELSE ARRAY[]::VARCHAR[]
        END as TagArray
    FROM Posts p
    WHERE p.CreationDate >= '2015-01-01'
),
ComplexQuery AS (
    SELECT 
        tu.UserId,
        tu.DisplayName,
        tu.Reputation,
        tu.TotalPosts,
        tu.Questions,
        tu.Answers,
        tu.Comments,
        tu.Badges,
        tu.LastPostDate,
        tu.TotalScore,
        tu.AvgScorePerPost,
        tu.TagSummary,
        tu.RankScore,
        tu.RankPosts,
        tu.ReputationQuantile,
        pa.PostId,
        pa.Title,
        pa.Body,
        pa.Score as PostScore,
        pa.ViewCount,
        pa.CreationDate as PostCreationDate,
        pa.PostTypeId,
        pa.AnswerCount,
        pa.CommentCount,
        pa.Tags as PostTags,
        pa.PostTypeDesc,
        pa.ScoreCategory,
        pa.HighScoreAnswers,
        pa.PreviousPostDate,
        pa.PreviousScore,
        pa.ScoreRank,
        pa.UserAvgScore,
        pa.TagArray,
        CASE 
            WHEN pa.ScoreRank <= 10 
            THEN CONCAT('Top ', pa.ScoreRank, ' Scoring Post')
            WHEN pa.ScoreRank BETWEEN 11 AND 50 
            THEN CONCAT('Mid ', pa.ScoreRank, ' Scoring Post')
            ELSE CONCAT('Lower ', pa.ScoreRank, ' Scoring Post')
        END as PostPerformanceTier,
        CASE 
            WHEN pa.Score > 0 AND pa.ViewCount > 0 
            THEN ROUND(CAST(pa.Score AS FLOAT) / pa.ViewCount * 1000, 2)
            ELSE 0 
        END as ScorePerThousandViews,
        COALESCE(
            (SELECT COUNT(*) 
             FROM PostHistory ph 
             WHERE ph.PostId = pa.PostId 
             AND ph.PostHistoryTypeId IN (1, 2, 4, 5, 6) 
             AND ph.CreationDate > '2020-01-01'),
            0
        ) as RecentEdits,
        CASE 
            WHEN pa.Tags IS NOT NULL 
            THEN LENGTH(pa.Tags)
            ELSE 0 
        END as TagLength,
        DATEDIFF('DAY', pa.CreationDate, CURRENT_TIMESTAMP) as DaysSincePost,
        IIF(pa.PreviousPostDate IS NOT NULL, 
            DATEDIFF('DAY', pa.PreviousPostDate, pa.CreationDate), 
            NULL
        ) as DaysBetweenPosts,
        IIF(pa.PreviousScore IS NOT NULL, 
            pa.Score - pa.PreviousScore, 
            NULL
        ) as ScoreChange
    FROM TopUsers tu
    INNER JOIN PostAnalysis pa ON tu.UserId = pa.OwnerUserId
    WHERE (
        pa.PostTypeDesc IN ('Question', 'Answer') 
        AND pa.PostScore > 0 
        AND pa.ViewCount > 10
    )
    AND (
        (tu.TotalPosts > 100 AND tu.Reputation > 10000)
        OR (tu.TotalPosts > 50 AND tu.Reputation > 5000)
        OR (tu.TotalPosts > 25 AND tu.Reputation > 1000)
    )
)
SELECT 
    *,
    CASE 
        WHEN TotalPosts > 50 
        THEN 'Highly Active'
        WHEN TotalPosts > 25 
        THEN 'Active'
        WHEN TotalPosts > 10 
        THEN 'Moderate'
        ELSE 'Low'
    END as ActivityLevel,
    CASE 
        WHEN ScorePerThousandViews > 5 
        THEN 'High Engagement'
        WHEN ScorePerThousandViews > 2 
        THEN 'Medium Engagement'
        ELSE 'Low Engagement'
    END as EngagementLevel,
    CASE 
        WHEN ReputationQuantile <= 3 
        THEN 'Top Tier'
        WHEN ReputationQuantile <= 6 
        THEN 'High Tier'
        WHEN ReputationQuantile <= 8 
        THEN 'Medium Tier'
        ELSE 'Low Tier'
    END as ReputationTier,
    COUNT(*) OVER () as TotalResults,
    RANK() OVER (ORDER BY PostScore DESC) as PostRank,
    PERCENT_RANK() OVER (ORDER BY PostScore DESC) as PostPercentile
FROM ComplexQuery
WHERE 
    (PostScore > (SELECT AVG(PostScore) FROM ComplexQuery) * 1.5)
    AND (
        (RECENTEDITS > 0 AND ScorePerThousandViews > 3)
        OR (PostTypeDesc = 'Question' AND AnswerCount >= 3)
        OR (PostTypeDesc = 'Answer' AND ScoreChange > 2)
    )
    AND (
        EXISTS (
            SELECT 1 FROM Tags t 
            WHERE t.TagName IN ('sql', 'python', 'java') 
            AND (COALESCE(pa.TagArray, ARRAY[]::VARCHAR[]) && ARRAY[t.TagName])
        )
    )
UNION ALL
SELECT 
    NULL as UserId,
    'TOTAL SUMMARY' as DisplayName,
    0 as Reputation,
    COUNT(*) as TotalPosts,
    0 as Questions,
    0 as Answers,
    0 as Comments,
    0 as Badges,
    NULL as LastPostDate,
    SUM(PostScore) as TotalScore,
    AVG(PostScore) as AvgScorePerPost,
    NULL as TagSummary,
    0 as RankScore,
    0 as RankPosts,
    0 as ReputationQuantile,
    NULL as PostId,
    NULL as Title,
    NULL as Body,
    NULL as PostScore,
    NULL as ViewCount,
    NULL as PostCreationDate,
    NULL as PostTypeId,
    NULL as AnswerCount,
    NULL as CommentCount,
    NULL as PostTags,
    NULL as PostTypeDesc,
    NULL as ScoreCategory,
    NULL as HighScoreAnswers,
    NULL as PreviousPostDate,
    NULL as PreviousScore,
    NULL as ScoreRank,
    NULL as UserAvgScore,
    NULL as TagArray,
    NULL as PostPerformanceTier,
    AVG(ScorePerThousandViews) as ScorePerThousandViews,
    NULL as RecentEdits,
    NULL as TagLength,
    NULL as DaysSincePost,
    NULL as DaysBetweenPosts,
    NULL as ScoreChange,
    'SUMMARY' as ActivityLevel,
    'AGGREGATE' as EngagementLevel,
    'OVERALL' as ReputationTier,
    COUNT(*) OVER () as TotalResults,
    0 as PostRank,
    0 as PostPercentile
FROM ComplexQuery
ORDER BY 
    CASE WHEN UserId IS NULL THEN 1 ELSE 0 END,
    PostScore DESC,
    TotalScore DESC
LIMIT 1000;
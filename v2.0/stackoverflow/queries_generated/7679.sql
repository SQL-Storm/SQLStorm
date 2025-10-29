-- {"query": "7679.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2228} 
WITH UserStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.ViewCount,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) as QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) as AnswerCount,
        SUM(COALESCE(p.Score, 0)) as TotalScore,
        MAX(p.CreationDate) as LatestPostDate,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount END) as AvgQuestionViews,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.ViewCount END) as AvgAnswerViews,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') as AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.ViewCount
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        PostCount,
        CommentCount,
        BadgeCount,
        QuestionCount,
        AnswerCount,
        TotalScore,
        LatestPostDate,
        AvgQuestionViews,
        AvgAnswerViews,
        AllTags,
        ROW_NUMBER() OVER (ORDER BY TotalScore DESC, Reputation DESC) as Rank,
        NTILE(100) OVER (ORDER BY TotalScore DESC) as Percentile
    FROM UserStats
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        COALESCE(p.ViewCount, 0) as WikiViews,
        COALESCE(p.Score, 0) as WikiScore,
        CASE 
            WHEN t.Count > 1000 THEN 'Very Popular'
            WHEN t.Count > 100 THEN 'Popular'
            WHEN t.Count > 50 THEN 'Moderate'
            ELSE 'Less Popular'
        END as PopularityLevel,
        LAG(t.Count) OVER (ORDER BY t.Count DESC) - t.Count as PopularityChange
    FROM Tags t
    LEFT JOIN Posts p ON t.WikiPostId = p.Id
),
PostActivity AS (
    SELECT 
        p.Id,
        p.Title,
        p.Body,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END as PostType,
        COALESCE(p.AnswerCount, 0) as AnswerCount,
        COALESCE(p.CommentCount, 0) as CommentCount,
        COALESCE(p.FavoriteCount, 0) as FavoriteCount,
        DATEDIFF(day, p.CreationDate, CURRENT_TIMESTAMP) as DaysSinceCreation,
        COALESCE(p.LastActivityDate, p.CreationDate) as LastActivity,
        CASE 
            WHEN DATEDIFF(day, p.CreationDate, CURRENT_TIMESTAMP) > 30 THEN 'Old'
            WHEN DATEDIFF(day, p.CreationDate, CURRENT_TIMESTAMP) > 7 THEN 'Recent'
            ELSE 'Fresh'
        END as AgeCategory,
        p.Tags,
        CASE 
            WHEN p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2 THEN 
                ARRAY_LENGTH(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><'), 1)
            ELSE 0 
        END as TagsCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as UserPostRank,
        RANK() OVER (ORDER BY p.Score DESC) as ScoreRank,
        DENSE_RANK() OVER (ORDER BY p.ViewCount DESC) as ViewRank
    FROM Posts p
    WHERE p.Id IS NOT NULL
),
ComplexAnalysis AS (
    SELECT 
        pa.Id,
        pa.Title,
        pa.Body,
        pa.Score,
        pa.ViewCount,
        pa.CreationDate,
        pa.OwnerUserId,
        pa.PostType,
        pa.AnswerCount,
        pa.CommentCount,
        pa.FavoriteCount,
        pa.DaysSinceCreation,
        pa.LastActivity,
        pa.AgeCategory,
        pa.Tags,
        pa.TagsCount,
        pa.UserPostRank,
        pa.ScoreRank,
        pa.ViewRank,
        tu.DisplayName as OwnerDisplayName,
        tu.Reputation as OwnerReputation,
        tu.PostCount as OwnerPostCount,
        tu.QuestionCount as OwnerQuestionCount,
        tu.AnswerCount as OwnerAnswerCount,
        tu.TotalScore as OwnerTotalScore,
        tu.Percentile as OwnerPercentile,
        ta.TagName,
        ta.Count as TagCount,
        ta.WikiViews,
        ta.WikiScore,
        CASE 
            WHEN pa.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'Above Average'
            WHEN pa.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) * 0.8 THEN 'Average'
            ELSE 'Below Average'
        END as ScorePerformance,
        CASE 
            WHEN pa.ViewCount > (SELECT AVG(ViewCount) FROM Posts) THEN 'Popular'
            WHEN pa.ViewCount > (SELECT AVG(ViewCount) FROM Posts) * 0.8 THEN 'Moderate'
            ELSE 'Low'
        END as ViewPerformance,
        CAST(CASE 
            WHEN pa.Tags IS NOT NULL AND LENGTH(pa.Tags) > 2 THEN 
                (ARRAY_LENGTH(string_to_array(SUBSTRING(pa.Tags, 2, LENGTH(pa.Tags)-2), '><'), 1) * pa.Score) / NULLIF(pa.ViewCount, 0)
            ELSE 0 
        END AS FLOAT) as TagScoreEfficiency,
        CASE 
            WHEN pa.Score > (SELECT AVG(Score) FROM Posts) 
                 AND pa.ViewCount > (SELECT AVG(ViewCount) FROM Posts) THEN 'High Impact'
            WHEN pa.Score > (SELECT AVG(Score) FROM Posts) 
                 OR pa.ViewCount > (SELECT AVG(ViewCount) FROM Posts) THEN 'Moderate Impact'
            ELSE 'Low Impact'
        END as ImpactCategory
    FROM PostActivity pa
    LEFT JOIN TopUsers tu ON pa.OwnerUserId = tu.UserId
    LEFT JOIN TagAnalysis ta ON pa.Tags IS NOT NULL 
        AND LENGTH(pa.Tags) > 2 
        AND ta.TagName IN (
            SELECT TRIM(UNNEST(string_to_array(SUBSTRING(pa.Tags, 2, LENGTH(pa.Tags)-2), '><')))
        )
    WHERE pa.OwnerUserId IS NOT NULL 
      AND pa.Score IS NOT NULL
)
SELECT 
    ca.Id,
    ca.Title,
    SUBSTRING(ca.Body, 1, 200) || '...' as BodySnippet,
    ca.Score,
    ca.ViewCount,
    ca.CreationDate,
    ca.OwnerUserId,
    ca.OwnerDisplayName,
    ca.OwnerReputation,
    ca.OwnerPostCount,
    ca.OwnerQuestionCount,
    ca.OwnerAnswerCount,
    ca.OwnerTotalScore,
    ca.OwnerPercentile,
    ca.PostType,
    ca.AnswerCount,
    ca.CommentCount,
    ca.FavoriteCount,
    ca.DaysSinceCreation,
    ca.LastActivity,
    ca.AgeCategory,
    ca.Tags,
    ca.TagsCount,
    ca.UserPostRank,
    ca.ScoreRank,
    ca.ViewRank,
    ca.TagName,
    ca.TagCount,
    ca.WikiViews,
    ca.WikiScore,
    ca.ScorePerformance,
    ca.ViewPerformance,
    ca.TagScoreEfficiency,
    ca.ImpactCategory,
    CASE 
        WHEN ca.TagScoreEfficiency > 10 THEN 'High'
        WHEN ca.TagScoreEfficiency > 5 THEN 'Medium'
        ELSE 'Low'
    END as EfficiencyLevel,
    COUNT(*) OVER () as TotalResults,
    ROW_NUMBER() OVER (ORDER BY ca.Score DESC, ca.ViewCount DESC) as OverallRank,
    PERCENT_RANK() OVER (ORDER BY ca.Score DESC) as ScorePercentile,
    NTILE(4) OVER (ORDER BY ca.ViewCount DESC) as ViewQuartile,
    LAG(ca.Score) OVER (ORDER BY ca.Score DESC) - ca.Score as ScoreDiffFromPrev,
    LEAD(ca.Score) OVER (ORDER BY ca.Score DESC) - ca.Score as ScoreDiffFromNext,
    AVG(ca.ViewCount) OVER (ORDER BY ca.Score DESC ROWS BETWEEN 10 PRECEDING AND 10 FOLLOWING) as MovingAvgViewCount,
    SUM(ca.Score) OVER (ORDER BY ca.CreationDate) as CumulativeScore,
    MAX(ca.Score) OVER (ORDER BY ca.OwnerUserId) as OwnerMaxScore,
    MIN(ca.ViewCount) OVER (ORDER BY ca.OwnerUserId) as OwnerMinViews,
    COUNT(ca.Id) OVER (PARTITION BY ca.OwnerUserId) as OwnerPostCount,
    CASE 
        WHEN ca.Score >= (SELECT MAX(Score) FROM Posts WHERE PostTypeId = 1) * 0.9 THEN 'Elite'
        WHEN ca.Score >= (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) * 1.5 THEN 'Above Average'
        ELSE 'Regular'
    END as QualityCategory,
    CASE 
        WHEN ca.ViewCount >= (SELECT AVG(ViewCount) FROM Posts) * 2 THEN 'Viral'
        WHEN ca.ViewCount >= (SELECT AVG(ViewCount) FROM Posts) THEN 'Popular'
        ELSE 'Standard'
    END as PopularityCategory,
    COALESCE(ca.OwnerDisplayName, 'Anonymous') as FinalDisplayName,
    COALESCE(ca.TagName, 'No Tags') as FinalTagName
FROM ComplexAnalysis ca
WHERE ca.Id IS NOT NULL
  AND ca.Score IS NOT NULL
  AND (ca.OwnerDisplayName IS NOT NULL OR ca.OwnerUserId IS NOT NULL)
  AND (ca.TagCount IS NOT NULL OR ca.Score >= 0)
  AND ca.DaysSinceCreation >= 0
  AND (ca.Score > 0 OR ca.ViewCount > 0)
ORDER BY ca.Score DESC, ca.ViewCount DESC, ca.CreationDate DESC
LIMIT 1000;
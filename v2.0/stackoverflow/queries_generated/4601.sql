-- {"query": "4601.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1360} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate ASC) AS rn_score,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) AS dr_score,
        LAG(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS PreviousScore,
        LEAD(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS NextScore,
        COALESCE(p.AnswerCount, 0) AS NonNullAnswerCount,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosedInt,
        SUM(COALESCE(c.Score, 0)) OVER (PARTITION BY p.Id ORDER BY c.CreationDate) AS CumulativeCommentScore
    FROM Posts AS p
    JOIN PostTypes AS pt ON p.PostTypeId = pt.Id
    LEFT JOIN Comments AS c ON p.Id = c.PostId
    WHERE p.CreationDate > '2023-01-01' AND p.Score > 5
),
HighImpactQuestions AS (
    SELECT
        rp.PostId,
        rp.Title,
        rp.CreationDate,
        rp.Score,
        rp.PostTypeName,
        rp.rn_score,
        rp.dr_score,
        rp.PreviousScore,
        rp.NextScore,
        rp.NonNullAnswerCount,
        rp.IsClosedInt,
        rp.CumulativeCommentScore,
        u.DisplayName AS OwnerDisplayName,
        u.Reputation AS OwnerReputation,
        CASE
            WHEN rp.NextScore - rp.PreviousScore > 10 THEN 'Significant Jump'
            WHEN rp.Score > 100 AND rp.AnswerCount > 10 THEN 'Highly Popular'
            ELSE 'Moderate Activity'
        END AS ActivityLevel
    FROM RankedPosts AS rp
    LEFT JOIN Users AS u ON rp.OwnerUserId = u.Id
    WHERE rp.rn_score <= 100 AND rp.dr_score <= 50
),
RelatedPostCounts AS (
    SELECT
        p.Id,
        COUNT(DISTINCT pl.RelatedPostId) AS NumberOfRelatedPosts
    FROM Posts AS p
    LEFT JOIN PostLinks AS pl ON p.Id = pl.PostId OR p.Id = pl.RelatedPostId
    GROUP BY p.Id
),
TagPerformance AS (
    SELECT
        t.TagName,
        AVG(p.Score) AS AveragePostScore,
        SUM(p.ViewCount) AS TotalViews,
        COUNT(p.Id) AS NumberOfPosts,
        (SELECT COUNT(DISTINCT UserId) FROM Votes WHERE PostId IN (SELECT Id FROM Posts WHERE Tags LIKE '%' || t.TagName || '%') AND VoteTypeId = 2) AS TotalUpvotes
    FROM Tags AS t
    JOIN Posts AS p ON p.Tags LIKE '%' || t.TagName || '%' AND p.PostTypeId = 1
    WHERE t.TagName NOT IN ('c#', 'java', 'python', 'javascript', 'sql')
    GROUP BY t.TagName
    HAVING COUNT(p.Id) > 50
)
SELECT
    hiq.PostId,
    hiq.Title,
    hiq.CreationDate,
    hiq.Score,
    hiq.PostTypeName,
    hiq.OwnerDisplayName,
    hiq.OwnerReputation,
    hiq.ActivityLevel,
    COALESCE(rpc.NumberOfRelatedPosts, 0) AS RelatedPostCount,
    tp.AveragePostScore AS AvgScoreForTopTag,
    tp.TotalViews AS TotalViewsForTopTag,
    (SELECT MAX(CreationDate) FROM Comments WHERE PostId = hiq.PostId) AS LastCommentDate,
    '---' AS Separator,
    tp.TagName AS TopPerformingTag,
    tp.NumberOfPosts AS PostsInTopTag,
    tp.TotalUpvotes AS UpvotesInTopTag,
    CASE
        WHEN hiq.Score > tp.AveragePostScore * 2 THEN 'Outperforming Tag Avg'
        WHEN hiq.Score < tp.AveragePostScore / 2 THEN 'Underperforming Tag Avg'
        ELSE 'On Par With Tag Avg'
    END AS PerformanceVsTag,
    UPPER(SUBSTRING(hiq.Title FROM 1 FOR 3)) || '-' || hiq.PostId AS CustomId
FROM HighImpactQuestions AS hiq
LEFT JOIN RelatedPostCounts AS rpc ON hiq.PostId = rpc.Id
LEFT JOIN TagPerformance AS tp ON hiq.Tags LIKE '%' || tp.TagName || '%'
WHERE tp.NumberOfPosts IS NOT NULL
UNION ALL
SELECT
    NULL,
    'Tag Performance Summary',
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL
UNION ALL
SELECT
    NULL AS PostId,
    TagName AS Title,
    NULL AS CreationDate,
    AveragePostScore AS Score,
    'TagSummary' AS PostTypeName,
    NULL AS OwnerDisplayName,
    NumberOfPosts AS OwnerReputation,
    NULL AS ActivityLevel,
    NULL AS RelatedPostCount,
    NULL AS AvgScoreForTopTag,
    TotalViews AS TotalViewsForTopTag,
    NULL AS LastCommentDate,
    NULL AS Separator,
    NULL AS TopPerformingTag,
    NULL AS PostsInTopTag,
    NULL AS UpvotesInTopTag,
    NULL AS PerformanceVsTag,
    NULL AS CustomId
FROM TagPerformance
ORDER BY Score DESC NULLS LAST, CreationDate ASC NULLS LAST;

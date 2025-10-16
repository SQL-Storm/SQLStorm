-- {"query": "15057.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 135430, "output_tokens": 39883} 
WITH UserPostActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        p.Id AS PostId,
        p.PostTypeId,
        p.Score,
        RANK() OVER (PARTITION BY u.Id ORDER BY p.Score DESC) AS PostScoreRank,
        COUNT(*) OVER (PARTITION BY u.Id) AS TotalUserPosts,
        AVG(p.Score) OVER (PARTITION BY u.Id) AS AvgUserPostScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId IN (1, 2)
    AND p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId IN (1, 2))
),
TagPopularity AS (
    SELECT 
        t.TagName,
        COUNT(*) AS TagCount,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS MedianTagScore
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    GROUP BY t.TagName
    HAVING COUNT(*) > 100
)
SELECT 
    upa.UserId,
    upa.DisplayName,
    upa.PostId,
    COALESCE(tp.TagName, 'Unknown') AS DominantTag,
    CASE 
        WHEN upa.PostScoreRank = 1 THEN 'Top Post'
        WHEN upa.PostScoreRank <= 3 THEN 'High Performer'
        ELSE 'Standard Post'
    END AS PostCategory,
    upa.Score,
    tp.TagCount,
    tp.MedianTagScore,
    ROUND(100.0 * upa.Score / NULLIF(upa.AvgUserPostScore, 0), 2) AS ScorePerformanceRatio
FROM UserPostActivity upa
LEFT JOIN TagPopularity tp ON upa.PostTypeId = 1 
    AND EXISTS (
        SELECT 1 
        FROM Posts p 
        WHERE p.Id = upa.PostId 
        AND p.Tags LIKE '%' || tp.TagName || '%'
    )
WHERE upa.TotalUserPosts > 5
    AND (upa.Score > 10 OR tp.TagCount > 500)
ORDER BY ScorePerformanceRatio DESC
LIMIT 500;
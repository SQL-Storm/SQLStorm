-- {"query": "15075.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 177460, "output_tokens": 52226} 
WITH RankedUserPosts AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        p.Id AS PostId,
        p.Score,
        p.CreationDate,
        DENSE_RANK() OVER (PARTITION BY u.Id ORDER BY p.Score DESC) AS ScoreRank,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) OVER (PARTITION BY u.Id) AS TotalUpvotes,
        COALESCE(p.AnswerCount, 0) + COALESCE(p.CommentCount, 0) AS TotalInteractions
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    WHERE 
        p.PostTypeId IN (1, 2)
        AND u.Reputation > 100
),
TagStatistics AS (
    SELECT 
        t.TagName,
        COUNT(DISTINCT p.Id) AS PostCount,
        AVG(p.Score) AS AverageTagScore,
        STRING_AGG(DISTINCT t.TagName, ',' ORDER BY t.TagName) OVER () AS AllTags
    FROM 
        Tags t
    JOIN 
        Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    GROUP BY 
        t.TagName
)
SELECT 
    r.UserId,
    r.DisplayName,
    r.PostId,
    r.Score,
    r.ScoreRank,
    r.TotalUpvotes,
    r.TotalInteractions,
    ts.TagName,
    ts.PostCount,
    ts.AverageTagScore,
    CASE 
        WHEN r.Score > (SELECT AVG(Score) FROM Posts) THEN 'High Performance'
        WHEN r.Score < (SELECT AVG(Score) FROM Posts) THEN 'Low Performance'
        ELSE 'Average Performance'
    END AS PerformanceCategory,
    ROUND(r.TotalUpvotes * 100.0 / NULLIF(r.TotalInteractions, 0), 2) AS UpvotePercentage
FROM 
    RankedUserPosts r
JOIN 
    TagStatistics ts ON EXISTS (
        SELECT 1 
        FROM Posts p 
        WHERE p.Id = r.PostId 
        AND p.Tags LIKE '%' || ts.TagName || '%'
    )
WHERE 
    r.ScoreRank <= 3
    AND r.TotalInteractions > 0
ORDER BY 
    r.TotalUpvotes DESC, 
    r.Score DESC
LIMIT 100;
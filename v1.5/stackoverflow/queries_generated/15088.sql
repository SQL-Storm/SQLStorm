-- {"query": "15088.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 207815, "output_tokens": 61099} 
WITH PostMetrics AS (
    SELECT 
        p.Id AS PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        COALESCE(u.Reputation, 0) AS UserReputation,
        EXTRACT(YEAR FROM p.CreationDate) AS PostYear,
        DENSE_RANK() OVER (PARTITION BY EXTRACT(YEAR FROM p.CreationDate) ORDER BY p.Score DESC) AS YearlyScoreRank,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) OVER (PARTITION BY p.OwnerUserId) AS TotalUpvotes,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentFrequency
    FROM 
        Posts p
    LEFT JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
),
TagPopularity AS (
    SELECT 
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS Tag,
        AVG(pm.Score) AS AvgTagScore,
        COUNT(*) AS TagCount
    FROM 
        Posts p
    JOIN 
        PostMetrics pm ON p.Id = pm.PostId
    WHERE 
        p.PostTypeId = 1
    GROUP BY 
        Tag
)
SELECT 
    pm.PostId,
    pm.PostYear,
    pm.UserReputation,
    pm.Score,
    pm.ViewCount,
    pm.YearlyScoreRank,
    pm.TotalUpvotes,
    pm.CommentFrequency,
    tp.Tag,
    tp.AvgTagScore,
    tp.TagCount,
    CASE 
        WHEN pm.Score > tp.AvgTagScore * 1.5 THEN 'High Impact'
        WHEN pm.Score < tp.AvgTagScore * 0.5 THEN 'Low Impact'
        ELSE 'Average Impact'
    END AS PostImpactCategory,
    ROUND(pm.Score * LOG(pm.ViewCount + 1), 2) AS ScoreViewProduct
FROM 
    PostMetrics pm
JOIN 
    TagPopularity tp ON tp.Tag IN (
        SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'))
        FROM Posts p
        WHERE p.Id = pm.PostId
    )
WHERE 
    pm.PostTypeId = 1 
    AND pm.PostYear BETWEEN 2010 AND 2020
    AND pm.UserReputation > 100
    AND pm.ViewCount > 50
ORDER BY 
    ScoreViewProduct DESC
LIMIT 1000;
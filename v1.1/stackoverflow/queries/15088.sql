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
        tag AS Tag,
        AVG(pm.Score) AS AvgTagScore,
        COUNT(*) AS TagCount
    FROM (
        SELECT p.Id AS pid, unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag
        FROM Posts p
        WHERE p.PostTypeId = 1
    ) pt
    JOIN PostMetrics pm ON pt.pid = pm.PostId
    GROUP BY 
        tag
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
    ROUND(CAST(pm.Score * LOG(pm.ViewCount + 1) AS numeric), 2) AS ScoreViewProduct
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
    ScoreViewProduct DESC,
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
    tp.TagCount
LIMIT 1000;
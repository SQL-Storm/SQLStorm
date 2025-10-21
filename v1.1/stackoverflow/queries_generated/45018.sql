-- {"query": "45018.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 331}
WITH RankedPosts AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.Score, 
        p.ViewCount,
        u.Reputation,
        pt.Name AS PostTypeName,
        DENSE_RANK() OVER (PARTITION BY u.Id ORDER BY p.Score DESC) AS UserPostRank,
        ROW_NUMBER() OVER (PARTITION BY u.Reputation > 10000 ORDER BY p.ViewCount DESC) AS PopularityRank
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    JOIN 
        PostTypes pt ON p.PostTypeId = pt.Id
    WHERE 
        p.PostTypeId = 1 
        AND p.CreationDate > '2015-01-01'
)
SELECT 
    PostTypeName,
    AVG(Score) AS AvgScore,
    MAX(ViewCount) AS MaxViews,
    COUNT(*) AS PostCount,
    SUM(Reputation) AS TotalUserReputation
FROM 
    RankedPosts
WHERE 
    UserPostRank <= 10 
    AND PopularityRank <= 100
GROUP BY 
    PostTypeName
ORDER BY 
    AvgScore DESC, 
    PostCount DESC
LIMIT 50;

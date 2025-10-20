-- {"query": "45066.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 151404, "output_tokens": 26801} 
WITH RankedUserPosts AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        p.Id AS PostId,
        p.Score,
        p.ViewCount,
        p.PostTypeId,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.Score DESC, p.ViewCount DESC) AS PostRank,
        COUNT(*) OVER (PARTITION BY u.Id) AS TotalUserPosts,
        AVG(p.Score) OVER (PARTITION BY u.Id) AS AvgUserPostScore
    FROM 
        Users u
    JOIN 
        Posts p ON u.Id = p.OwnerUserId
    WHERE 
        p.PostTypeId IN (1,2)
        AND u.Reputation > 1000
),
TagAnalytics AS (
    SELECT 
        PostId,
        unnest(string_to_array(substring(Tags, 2, length(Tags)-2), '><')) AS Tag,
        Score
    FROM 
        RankedUserPosts
)
SELECT 
    Tag,
    COUNT(DISTINCT PostId) AS PostCount,
    ROUND(AVG(Score), 2) AS AvgTagScore,
    MAX(Score) AS MaxTagScore
FROM 
    TagAnalytics
WHERE 
    PostRank <= 10
    AND TotalUserPosts > 5
GROUP BY 
    Tag
HAVING 
    COUNT(DISTINCT PostId) > 100
ORDER BY 
    AvgTagScore DESC, 
    PostCount DESC
LIMIT 50;
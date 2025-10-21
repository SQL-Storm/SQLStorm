-- {"query": "45094.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 215636, "output_tokens": 38422} 
WITH RankedPosts AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.Score, 
        p.ViewCount,
        p.AnswerCount,
        u.DisplayName,
        u.Reputation,
        DENSE_RANK() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS PostRank,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.CreationDate) AS UserPostSequence
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.PostTypeId = 1 
        AND p.ClosedDate IS NULL
        AND p.Score > 10
        AND p.CreationDate > '2018-01-01'
), 
TagAnalysis AS (
    SELECT 
        t.TagName, 
        COUNT(DISTINCT p.Id) AS TagPostCount,
        AVG(p.Score) AS AvgTagScore,
        MAX(p.ViewCount) AS MaxTagViewCount
    FROM 
        Posts p
    CROSS JOIN 
        LATERAL string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') tag
    JOIN 
        Tags t ON tag = t.TagName
    GROUP BY 
        t.TagName
)
SELECT 
    rp.Id,
    rp.Title,
    rp.Score,
    rp.ViewCount,
    rp.DisplayName,
    rp.Reputation,
    rp.PostRank,
    rp.UserPostSequence,
    ta.TagName,
    ta.TagPostCount,
    ta.AvgTagScore,
    ta.MaxTagViewCount
FROM 
    RankedPosts rp
JOIN 
    Posts p ON rp.Id = p.Id
CROSS JOIN 
    LATERAL string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') tag
JOIN 
    TagAnalysis ta ON tag = ta.TagName
WHERE 
    rp.PostRank <= 100
    AND ta.TagPostCount > 50
ORDER BY 
    rp.PostRank, 
    ta.TagPostCount DESC
LIMIT 1000;
-- {"query": "31031.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 330} 

WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.ViewCount,
        p.Score,
        p.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS Rank,
        u.DisplayName AS OwnerDisplayName,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.PostTypeId = 1 AND  -- Only questions
        p.CreationDate >= NOW() - INTERVAL '1 year'
),
TopPosts AS (
    SELECT 
        rp.PostId, 
        rp.Title, 
        rp.ViewCount, 
        rp.Score, 
        rp.CreationDate, 
        rp.OwnerDisplayName, 
        rp.CommentCount
    FROM 
        RankedPosts rp
    WHERE 
        rp.Rank <= 5  -- Top 5 questions per user
)
SELECT 
    tp.OwnerDisplayName,
    COUNT(tp.PostId) AS NumberOfTopPosts,
    AVG(tp.ViewCount) AS AverageViewCount,
    AVG(tp.Score) AS AverageScore,
    EXTRACT(MONTH FROM tp.CreationDate) AS CreationMonth
FROM 
    TopPosts tp
GROUP BY 
    tp.OwnerDisplayName, 
    EXTRACT(MONTH FROM tp.CreationDate)
ORDER BY 
    CreationMonth, 
    NumberOfTopPosts DESC;

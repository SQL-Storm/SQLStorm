-- {"query": "31006.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 430} 

WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        COUNT(v.Id) AS VoteCount,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY p.CreationDate DESC) AS rn
    FROM 
        Posts p
    LEFT JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Votes v ON p.Id = v.PostId 
    WHERE 
        p.CreationDate > NOW() - INTERVAL '1 year' 
    GROUP BY 
        p.Id, u.DisplayName, p.Title, p.CreationDate, p.Score, p.ViewCount
),
TopPosts AS (
    SELECT 
        PostId, 
        Title, 
        OwnerDisplayName, 
        CreationDate, 
        Score, 
        ViewCount, 
        VoteCount
    FROM 
        RankedPosts
    WHERE 
        rn = 1
    ORDER BY 
        VoteCount DESC, 
        Score DESC 
    LIMIT 10
)
SELECT 
    tp.Title,
    tp.OwnerDisplayName,
    tp.CreationDate,
    tp.Score,
    tp.ViewCount,
    CASE 
        WHEN tp.Score >= 50 THEN 'High Score' 
        WHEN tp.Score < 50 AND tp.Score >= 10 THEN 'Medium Score' 
        ELSE 'Low Score' 
    END AS ScoreCategory,
    STRING_AGG(DISTINCT t.TagName, ', ') AS Tags
FROM 
    TopPosts tp
LEFT JOIN 
    Posts p ON tp.PostId = p.Id
LEFT JOIN 
    STRING_TO_ARRAY(p.Tags, ',') AS tag_list ON TRUE 
LEFT JOIN 
    Tags t ON t.TagName = TRIM(tag_list)
GROUP BY 
    tp.Title, tp.OwnerDisplayName, tp.CreationDate, tp.Score, tp.ViewCount
ORDER BY 
    tp.Score DESC, 
    tp.ViewCount DESC;

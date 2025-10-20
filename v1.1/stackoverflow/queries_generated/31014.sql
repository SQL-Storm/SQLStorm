-- {"query": "31014.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 372} 

WITH RankedPosts AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.CreationDate, 
        p.ViewCount, 
        p.Score, 
        u.DisplayName AS OwnerDisplayName,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COALESCE(SUM(v.BountyAmount), 0) AS TotalBounty,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY p.CreationDate DESC) AS rn
    FROM 
        Posts p
    LEFT JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (8, 9) -- BountyStart, BountyClose
    WHERE 
        p.PostTypeId = 1 -- Only questions
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.ViewCount, p.Score, u.DisplayName
),
TopPosts AS (
    SELECT 
        rp.*, 
        RANK() OVER (ORDER BY rp.Score DESC, rp.ViewCount DESC) AS RankScore
    FROM 
        RankedPosts rp
    WHERE 
        rp.rn = 1 -- Selecting the main posts only
)
SELECT 
    tp.Id, 
    tp.Title, 
    tp.CreationDate, 
    tp.ViewCount, 
    tp.Score, 
    tp.OwnerDisplayName,
    tp.CommentCount,
    tp.TotalBounty,
    tp.RankScore
FROM 
    TopPosts tp
WHERE 
    tp.RankScore <= 10 -- Top 10 posts
ORDER BY 
    tp.Score DESC, 
    tp.ViewCount DESC;

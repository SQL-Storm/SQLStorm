-- {"query": "31062.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 500} 

WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.Title,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.LastActivityDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS Rank
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.PostTypeId = 1 AND
        p.CreationDate >= NOW() - INTERVAL '1 year'
),
TopPosts AS (
    SELECT 
        rp.Id,
        rp.Title,
        rp.OwnerDisplayName,
        rp.Score,
        rp.ViewCount,
        rp.CreationDate,
        rp.LastActivityDate
    FROM 
        RankedPosts rp
    WHERE 
        rp.Rank = 1
),
PostStats AS (
    SELECT 
        tp.Id,
        tp.Title,
        tp.OwnerDisplayName,
        tp.Score,
        tp.ViewCount,
        tp.CreationDate,
        tp.LastActivityDate,
        COUNT(c.Id) AS CommentCount,
        COUNT(v.Id) AS VoteCount
    FROM 
        TopPosts tp
    LEFT JOIN 
        Comments c ON tp.Id = c.PostId
    LEFT JOIN 
        Votes v ON tp.Id = v.PostId
    GROUP BY 
        tp.Id, tp.Title, tp.OwnerDisplayName, tp.Score, tp.ViewCount, tp.CreationDate, tp.LastActivityDate
)
SELECT 
    ps.Id,
    ps.Title,
    ps.OwnerDisplayName,
    ps.Score,
    ps.ViewCount,
    ps.CommentCount,
    ps.VoteCount,
    CASE 
        WHEN ps.Score >= 10 THEN 'High Score'
        WHEN ps.Score BETWEEN 5 AND 9 THEN 'Moderate Score'
        ELSE 'Low Score'
    END AS ScoreCategory,
    EXTRACT(EPOCH FROM (NOW() - ps.CreationDate)) / 86400 AS DaysSinceCreation,
    EXTRACT(EPOCH FROM (NOW() - ps.LastActivityDate)) / 86400 AS DaysSinceLastActivity
FROM 
    PostStats ps
WHERE 
    ps.CommentCount > 0 OR ps.VoteCount > 0
ORDER BY 
    ps.Score DESC, ps.ViewCount DESC;

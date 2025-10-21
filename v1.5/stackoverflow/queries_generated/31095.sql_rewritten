-- {"query": "31095.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 321} 
WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.CreationDate,
        u.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS Rank
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year' 
        AND p.Score IS NOT NULL
),
TopPosts AS (
    SELECT 
        PostId,
        Title,
        OwnerDisplayName,
        Score,
        CreationDate
    FROM 
        RankedPosts
    WHERE 
        Rank <= 10
)
SELECT 
    tp.Title,
    tp.OwnerDisplayName,
    tp.Score,
    tp.CreationDate,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = tp.PostId AND v.VoteTypeId = 2) AS UpVotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = tp.PostId AND v.VoteTypeId = 3) AS DownVotes,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = tp.PostId) AS CommentCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = tp.PostId AND ph.PostHistoryTypeId IN (10, 11)) AS ClosureHistoryCount
FROM 
    TopPosts tp
ORDER BY 
    tp.Score DESC,
    tp.CreationDate DESC;
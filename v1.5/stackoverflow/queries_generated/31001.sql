-- {"query": "31001.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 365} 

WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId, 
        p.Title,
        p.CreationDate,
        p.Score,
        u.DisplayName AS OwnerDisplayName,
        COUNT(c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate DESC) AS Rank
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    WHERE 
        p.CreationDate > NOW() - INTERVAL '1 year' 
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.Score, u.DisplayName
),
TopPosts AS (
    SELECT 
        PostId, Title, CreationDate, Score, OwnerDisplayName, CommentCount, UpVotes, DownVotes 
    FROM 
        RankedPosts 
    WHERE 
        Rank <= 10
)
SELECT 
    tp.Title, 
    tp.OwnerDisplayName, 
    tp.Score, 
    tp.CommentCount, 
    tp.UpVotes, 
    tp.DownVotes,
    (SELECT COUNT(url.Id) 
     FROM PostLinks url 
     WHERE url.PostId = tp.PostId AND url.LinkTypeId = 1) AS NumberOfLinks
FROM 
    TopPosts tp
ORDER BY 
    tp.Score DESC;

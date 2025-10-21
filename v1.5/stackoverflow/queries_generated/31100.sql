-- {"query": "31100.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 378} 

WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId, 
        p.Title, 
        p.CreationDate, 
        u.DisplayName AS OwnerDisplayName, 
        COUNT(c.Id) AS CommentCount,
        COUNT(v.Id) AS VoteCount,
        ROW_NUMBER() OVER(PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate DESC) AS RankByScore
    FROM 
        Posts p
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3) -- Only UpMod and DownMod votes
    LEFT JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.CreationDate >= NOW() - INTERVAL '1 year'
    GROUP BY 
        p.Id, p.Title, p.CreationDate, u.DisplayName
),
TopPosts AS (
    SELECT 
        PostId, 
        Title, 
        CreationDate, 
        OwnerDisplayName, 
        CommentCount, 
        VoteCount
    FROM 
        RankedPosts
    WHERE 
        RankByScore <= 10
)
SELECT 
    tp.PostId, 
    tp.Title, 
    tp.CreationDate, 
    tp.OwnerDisplayName, 
    tp.CommentCount, 
    tp.VoteCount,
    t.TagName,
    t.Count AS TagUsageCount
FROM 
    TopPosts tp
LEFT JOIN 
    unnest(string_to_array((SELECT Tags FROM Posts WHERE Id = tp.PostId), ',')) AS tag ON TRUE
LEFT JOIN 
    Tags t ON tag = t.TagName
ORDER BY 
    tp.VoteCount DESC, tp.CommentCount DESC;

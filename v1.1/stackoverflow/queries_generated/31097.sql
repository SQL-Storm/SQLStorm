-- {"query": "31097.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 428} 

WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS Rank,
        ARRAY_AGG(DISTINCT t.TagName) AS Tags
    FROM 
        Posts p
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    LEFT JOIN 
        LATERAL unnest(string_to_array(p.Tags, '><')) AS tag_id(t) ON true
    LEFT JOIN 
        Tags t ON t.TagName = tag_id.t
    WHERE 
        p.PostTypeId = 1 AND -- Select only Questions
        p.CreationDate >= NOW() - INTERVAL '30 days' -- Last 30 days
    GROUP BY 
        p.Id
),
TopPosts AS (
    SELECT 
        PostId,
        Title,
        CreationDate,
        Score,
        ViewCount,
        CommentCount,
        UpVotes,
        DownVotes,
        Rank,
        Tags
    FROM 
        RankedPosts
    WHERE 
        Rank <= 10 -- Get top 10 posts
)
SELECT 
    tp.PostId,
    tp.Title,
    tp.CreationDate,
    tp.Score,
    tp.ViewCount,
    tp.CommentCount,
    tp.UpVotes,
    tp.DownVotes,
    tp.Tags,
    CASE 
        WHEN tp.Score >= 100 THEN 'Hot'
        WHEN tp.Score BETWEEN 50 AND 99 THEN 'Trending'
        ELSE 'New'
    END AS PopularityStatus
FROM 
    TopPosts tp
ORDER BY 
    tp.Score DESC;

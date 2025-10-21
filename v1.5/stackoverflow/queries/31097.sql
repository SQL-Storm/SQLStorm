WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
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
        p.PostTypeId = 1 AND
        p.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30 days')
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount
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
        Rank <= 10
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
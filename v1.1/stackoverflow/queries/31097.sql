WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpVotes,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownVotes,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS Rank,
        ARRAY_AGG(DISTINCT t.TagName) AS Tags
    FROM 
        Posts p
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    LEFT JOIN 
        -- split tags string like '<tag1><tag2>' into rows; using standard SQL approach with regexp_split_to_table where available
        LATERAL (
            SELECT regexp_split_to_table(TRIM(BOTH '<>' FROM p.Tags), '><') AS TagName
        ) tag_values ON TRUE
    LEFT JOIN 
        Tags t ON t.TagName = tag_values.TagName
    WHERE 
        p.PostTypeId = 1
        AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY)
    GROUP BY 
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags
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
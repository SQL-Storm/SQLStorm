WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.ViewCount,
        p.Score,
        COUNT(c.Id) AS CommentCount,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS Rank
    FROM 
        Posts p
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    WHERE 
        p.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '1 year'
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.ViewCount, p.Score, p.PostTypeId
), PopularPosts AS (
    SELECT 
        rp.*,
        CASE 
            WHEN rp.Rank <= 10 THEN 'Top 10'
            WHEN rp.Rank <= 50 THEN 'Top 50'
            ELSE 'Others'
        END AS Category
    FROM 
        RankedPosts rp
)
SELECT 
    pp.PostId,
    pp.Title,
    pp.CreationDate,
    pp.ViewCount,
    pp.Score,
    pp.CommentCount,
    pp.UpVotes,
    pp.DownVotes,
    pp.Category,
    COALESCE(u.DisplayName, 'Anonymous') AS AuthorName, 
    u.Reputation AS AuthorReputation
FROM 
    PopularPosts pp
LEFT JOIN 
    Users u ON pp.PostId = u.Id
WHERE 
    pp.ViewCount > 1000
ORDER BY 
    pp.Score DESC, pp.ViewCount DESC;
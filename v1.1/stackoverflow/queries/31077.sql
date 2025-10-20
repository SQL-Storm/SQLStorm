WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.ViewCount,
        p.Score,
        COUNT(c.Id) AS CommentCount,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotes,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS Rank,
        p.PostTypeId
    FROM 
        Posts p
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    WHERE 
        p.CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '1' YEAR)
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.ViewCount, p.Score, p.PostTypeId
), PopularPosts AS (
    SELECT 
        rp.PostId,
        rp.Title,
        rp.CreationDate,
        rp.ViewCount,
        rp.Score,
        rp.CommentCount,
        rp.UpVotes,
        rp.DownVotes,
        rp.Rank,
        CASE 
            WHEN rp.Rank <= 10 THEN 'Top 10'
            WHEN rp.Rank <= 50 THEN 'Top 50'
            ELSE 'Others'
        END AS Category,
        rp.PostTypeId
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
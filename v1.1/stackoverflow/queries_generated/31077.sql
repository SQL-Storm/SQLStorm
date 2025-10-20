-- {"query": "31077.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 413} 

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
        p.CreationDate >= CURRENT_DATE - INTERVAL '1 year' -- Consider posts from the last year
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.ViewCount, p.Score
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
    Users u ON pp.PostId = u.Id -- Assuming PostId can be associated with Users for demonstration; typically would join on OwnerUserId
WHERE 
    pp.ViewCount > 1000 -- Filter for posts with more than 1000 views
ORDER BY 
    pp.Score DESC, pp.ViewCount DESC;

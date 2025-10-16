-- {"query": "1069.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 447} 

WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId, 
        p.Title, 
        p.CreationDate, 
        p.Score, 
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS Rank,
        COUNT(c.Id) AS CommentCount
    FROM 
        Posts p
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    WHERE 
        p.CreationDate >= NOW() - INTERVAL '1 year'
    GROUP BY 
        p.Id
), 
PopularTags AS (
    SELECT 
        UNNEST(string_to_array(p.Tags, ',')) AS Tag, 
        COUNT(*) AS PostCount
    FROM 
        Posts p
    GROUP BY 
        Tag
    HAVING 
        COUNT(*) > 5
), 
PostVotes AS (
    SELECT 
        p.Id AS PostId, 
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes, 
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM 
        Posts p
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    GROUP BY 
        p.Id
)
SELECT 
    rp.PostId, 
    rp.Title, 
    rp.CreationDate, 
    rp.Score, 
    rp.CommentCount, 
    pt.Tag, 
    COALESCE(pv.UpVotes, 0) AS TotalUpVotes, 
    COALESCE(pv.DownVotes, 0) AS TotalDownVotes,
    (COALESCE(pv.UpVotes, 0) - COALESCE(pv.DownVotes, 0)) AS NetVotes
FROM 
    RankedPosts rp
INNER JOIN 
    PopularTags pt ON rp.Title ILIKE '%' || pt.Tag || '%'
LEFT JOIN 
    PostVotes pv ON rp.PostId = pv.PostId
WHERE 
    rp.Rank <= 5
ORDER BY 
    rp.Score DESC, 
    NetVotes DESC
LIMIT 
    100;

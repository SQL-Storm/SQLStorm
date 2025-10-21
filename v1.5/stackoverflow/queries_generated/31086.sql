-- {"query": "31086.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 524} 

WITH RecentPosts AS (
    SELECT 
        p.Id AS PostId, 
        p.Title, 
        p.ViewCount, 
        p.CreationDate, 
        u.DisplayName AS OwnerDisplayName, 
        COUNT(c.Id) AS CommentCount, 
        SUM(v.VoteTypeId = 2) AS UpVotes, 
        SUM(v.VoteTypeId = 3) AS DownVotes
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId AND v.UserId IS NOT NULL
    WHERE 
        p.CreationDate >= NOW() - INTERVAL '30 days' 
        AND p.PostTypeId = 1 -- Only questions
    GROUP BY 
        p.Id, u.DisplayName
), 

RankedPosts AS (
    SELECT 
        PostId, 
        Title, 
        ViewCount, 
        CreationDate, 
        OwnerDisplayName, 
        CommentCount, 
        UpVotes, 
        DownVotes, 
        RANK() OVER (ORDER BY ViewCount DESC) AS ViewRank,
        RANK() OVER (ORDER BY UpVotes - DownVotes DESC) AS VoteRank
    FROM 
        RecentPosts
) 

SELECT 
    rp.PostId, 
    rp.Title, 
    rp.ViewCount, 
    rp.OwnerDisplayName, 
    rp.CommentCount, 
    rp.UpVotes, 
    rp.DownVotes,
    CASE 
        WHEN rp.ViewRank = 1 THEN 'Most Viewed' 
        WHEN rp.VoteRank = 1 THEN 'Most Voted' 
        ELSE 'Regular' 
    END AS PostType,
    COALESCE(CAST(pht.Comments AS json), '[]') AS RecentEdits
FROM 
    RankedPosts rp
LEFT JOIN 
    (
        SELECT 
            p.Id AS PostId, 
            JSON_AGG(ph.Comment ORDER BY ph.CreationDate DESC) AS Comments 
        FROM 
            PostHistory ph 
        JOIN 
            Posts p ON ph.PostId = p.Id 
        WHERE 
            p.PostTypeId = 1 
            AND ph.CreationDate >= NOW() - INTERVAL '30 days'
        GROUP BY 
            p.Id
    ) pht ON rp.PostId = pht.PostId
ORDER BY 
    rp.ViewRank, rp.VoteRank;

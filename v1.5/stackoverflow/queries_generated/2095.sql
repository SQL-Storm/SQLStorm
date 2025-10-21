-- {"query": "2095.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 485} 

WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        u.Id AS UserId,
        u.DisplayName,
        p.Score,
        RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS PostRank
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.PostTypeId = 1 -- Questions only
),
VoteSummary AS (
    SELECT 
        PostId,
        SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS UpvoteCount,
        SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS DownvoteCount
    FROM 
        Votes v
    JOIN 
        VoteTypes vt ON v.VoteTypeId = vt.Id
    GROUP BY 
        PostId
),
MergedPosts AS (
    SELECT
        r.PostId,
        r.Title,
        r.CreationDate,
        r.UserId,
        r.DisplayName,
        r.Score,
        vs.UpvoteCount,
        vs.DownvoteCount,
        COALESCE(vs.UpvoteCount, 0) - COALESCE(vs.DownvoteCount, 0) AS NetVotes
    FROM
        RankedPosts r
    LEFT JOIN
        VoteSummary vs ON r.PostId = vs.PostId
)
SELECT
    mp.PostId,
    mp.Title,
    mp.DisplayName,
    mp.Score,
    mp.UpvoteCount,
    mp.DownvoteCount,
    mp.NetVotes,
    COALESCE(b.Name, 'No Badge') AS BadgeName,
    COUNT(c.Id) AS CommentCount
FROM
    MergedPosts mp
LEFT JOIN 
    Badges b ON mp.UserId = b.UserId AND b.Class = 1 -- Gold Badges
LEFT JOIN
    Comments c ON mp.PostId = c.PostId
WHERE
    mp.PostRank = 1
GROUP BY
    mp.PostId, mp.Title, mp.DisplayName, mp.Score, mp.UpvoteCount, mp.DownvoteCount, mp.NetVotes, b.Name
HAVING 
    COUNT(c.Id) > 5
ORDER BY
    mp.NetVotes DESC, mp.CreationDate ASC;

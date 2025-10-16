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
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteCount
    FROM 
        Votes v
    GROUP BY 
        v.PostId
),
MergedPosts AS (
    SELECT
        r.PostId,
        r.Title,
        r.CreationDate,
        r.UserId,
        r.DisplayName,
        r.Score,
        COALESCE(vs.UpvoteCount, 0) AS UpvoteCount,
        COALESCE(vs.DownvoteCount, 0) AS DownvoteCount,
        COALESCE(vs.UpvoteCount, 0) - COALESCE(vs.DownvoteCount, 0) AS NetVotes,
        r.PostRank
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
    COUNT(c.Id) AS CommentCount,
    mp.CreationDate
FROM
    MergedPosts mp
LEFT JOIN 
    Badges b ON mp.UserId = b.UserId AND b.Class = 1 -- Gold Badges
LEFT JOIN
    Comments c ON mp.PostId = c.PostId
WHERE
    mp.PostRank = 1
GROUP BY
    mp.PostId,
    mp.Title,
    mp.DisplayName,
    mp.Score,
    mp.UpvoteCount,
    mp.DownvoteCount,
    mp.NetVotes,
    b.Name,
    mp.CreationDate
HAVING 
    COUNT(c.Id) > 5
ORDER BY
    mp.NetVotes DESC,
    mp.CreationDate ASC;
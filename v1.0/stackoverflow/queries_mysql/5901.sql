
WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.CreationDate,
        p.ViewCount,
        u.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate DESC) AS Rank
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.PostTypeId = 1 AND 
        p.CreationDate >= NOW() - INTERVAL 30 DAY
),
TopPosts AS (
    SELECT 
        r.PostId,
        r.Title,
        r.Score,
        r.CreationDate,
        r.ViewCount,
        r.OwnerDisplayName
    FROM 
        RankedPosts r
    WHERE 
        r.Rank <= 5
),
PostVoteStats AS (
    SELECT 
        p.Id AS PostId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotes,
        COUNT(v.Id) AS TotalVotes
    FROM 
        Posts p
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    GROUP BY 
        p.Id
),
FinalOutput AS (
    SELECT 
        t.PostId,
        t.Title,
        t.Score,
        t.CreationDate,
        t.ViewCount,
        t.OwnerDisplayName,
        v.UpVotes,
        v.DownVotes,
        v.TotalVotes
    FROM 
        TopPosts t
    LEFT JOIN 
        PostVoteStats v ON t.PostId = v.PostId
)
SELECT 
    f.*,
    COALESCE(f.UpVotes, 0) - COALESCE(f.DownVotes, 0) AS NetVotes
FROM 
    FinalOutput f
ORDER BY 
    f.Score DESC, f.CreationDate DESC;

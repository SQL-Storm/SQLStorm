
WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        COUNT(DISTINCT c.Id) AS CommentsCount,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpVotes,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownVotes,
        SUM(COALESCE(b.Class, 0)) AS TotalBadgeClass,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS RecentPostRank
    FROM 
        Posts p
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    LEFT JOIN 
        Badges b ON p.OwnerUserId = b.UserId
    WHERE 
        p.CreationDate >= '2024-10-01 12:34:56' - INTERVAL 1 YEAR 
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.OwnerUserId
),
TopUserPosts AS (
    SELECT 
        rp.PostId,
        rp.Title,
        rp.CreationDate,
        u.DisplayName AS OwnerDisplayName,
        rp.CommentsCount,
        rp.UpVotes,
        rp.DownVotes,
        rp.TotalBadgeClass
    FROM 
        RankedPosts rp
    JOIN 
        Users u ON rp.OwnerUserId = u.Id
    WHERE 
        rp.RecentPostRank = 1
    ORDER BY 
        rp.UpVotes - rp.DownVotes DESC, rp.CommentsCount DESC
    LIMIT 10
)
SELECT 
    tup.Title,
    tup.CreationDate,
    tup.OwnerDisplayName,
    tup.CommentsCount,
    tup.UpVotes,
    tup.DownVotes,
    tup.TotalBadgeClass
FROM 
    TopUserPosts tup
JOIN 
    PostHistory ph ON tup.PostId = ph.PostId
WHERE 
    ph.CreationDate >= '2024-10-01 12:34:56' - INTERVAL 6 MONTH
    AND ph.PostHistoryTypeId = 10  
ORDER BY 
    tup.UpVotes DESC;

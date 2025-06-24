
WITH RecentActivity AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        u.DisplayName AS OwnerDisplayName,
        COUNT(c.Id) AS CommentCount,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVoteCount,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVoteCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS ActivityRank
    FROM 
        Posts p
    LEFT JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    WHERE 
        p.CreationDate >= CAST('2024-10-01 12:34:56' AS DATETIME) - INTERVAL 30 DAY
    GROUP BY 
        p.Id, p.Title, p.CreationDate, u.DisplayName, p.OwnerUserId, p.LastActivityDate
),
CommentedPosts AS (
    SELECT 
        PostId, 
        COUNT(*) AS CommentedCount
    FROM 
        Comments
    GROUP BY 
        PostId
),
TopRecentPosts AS (
    SELECT 
        ra.PostId,
        ra.Title,
        ra.CreationDate,
        ra.OwnerDisplayName,
        ra.CommentCount,
        ra.UpVoteCount,
        ra.DownVoteCount,
        cp.CommentedCount,
        ROW_NUMBER() OVER (ORDER BY ra.UpVoteCount DESC, ra.CommentCount DESC) AS Rank
    FROM 
        RecentActivity ra
    LEFT JOIN 
        CommentedPosts cp ON ra.PostId = cp.PostId
)
SELECT 
    PostId,
    Title,
    CreationDate,
    OwnerDisplayName,
    CommentCount,
    UpVoteCount,
    DownVoteCount,
    CommentedCount
FROM 
    TopRecentPosts
WHERE 
    Rank <= 10
ORDER BY 
    UpVoteCount DESC, CommentCount DESC;

WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        u.DisplayName AS OwnerDisplayName,
        COUNT(c.Id) AS CommentCount,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVoteCount,
        p.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.CreationDate DESC) AS PostRank,
        u.Id AS OwnerUserId
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    LEFT JOIN 
        VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE 
        p.PostTypeId IN (1, 2)
    GROUP BY 
        p.Id, p.Title, u.DisplayName, p.CreationDate, u.Id
),
TopPosts AS (
    SELECT 
        PostId, Title, OwnerDisplayName, CommentCount, UpVoteCount, DownVoteCount
    FROM 
        RankedPosts
    WHERE 
        PostRank = 1
)
SELECT 
    tp.PostId,
    tp.Title,
    tp.OwnerDisplayName,
    tp.CommentCount,
    tp.UpVoteCount,
    tp.DownVoteCount,
    COALESCE(SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END), 0) AS CloseCount,
    COALESCE(SUM(CASE WHEN ph.PostHistoryTypeId = 12 THEN 1 ELSE 0 END), 0) AS DeleteCount
FROM 
    TopPosts tp
LEFT JOIN 
    PostHistory ph ON tp.PostId = ph.PostId
GROUP BY 
    tp.PostId, tp.Title, tp.OwnerDisplayName, tp.CommentCount, tp.UpVoteCount, tp.DownVoteCount
ORDER BY 
    tp.UpVoteCount DESC, tp.CommentCount DESC
LIMIT 10;
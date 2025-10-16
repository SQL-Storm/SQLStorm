WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        u.DisplayName AS OwnerDisplayName,
        COUNT(c.Id) AS CommentCount,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotes,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotes,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS PostRank
    FROM 
        Posts p
    LEFT JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    WHERE 
        p.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR)
    GROUP BY 
        p.Id,
        p.Title,
        p.CreationDate,
        u.DisplayName,
        p.PostTypeId
),
TopPosts AS (
    SELECT 
        rp.PostId,
        rp.Title,
        rp.OwnerDisplayName,
        rp.CommentCount,
        rp.UpVotes,
        rp.DownVotes
    FROM 
        RankedPosts rp
    WHERE 
        rp.PostRank <= 10
),
PostDetails AS (
    SELECT 
        tp.PostId,
        tp.Title,
        tp.OwnerDisplayName,
        tp.CommentCount,
        tp.UpVotes,
        tp.DownVotes,
        (
         SELECT MAX(ph.CreationDate) 
         FROM PostHistory ph 
         WHERE ph.PostId = tp.PostId AND ph.PostHistoryTypeId IN (10, 11)
        ) AS LastCloseOpenDate
    FROM 
        TopPosts tp
)
SELECT 
    pd.Title,
    pd.OwnerDisplayName,
    pd.CommentCount,
    pd.UpVotes,
    pd.DownVotes,
    CASE 
        WHEN pd.LastCloseOpenDate IS NOT NULL THEN 'Closed/Open'
        ELSE 'Active'
    END AS PostStatus,
    CASE 
        WHEN pd.UpVotes = 0 THEN NULL
        ELSE ROUND( (CAST(pd.UpVotes AS DECIMAL) / NULLIF((pd.UpVotes + pd.DownVotes), 0) * 100), 2)
    END AS UpVotePercentage
FROM 
    PostDetails pd
ORDER BY 
    pd.UpVotes DESC;
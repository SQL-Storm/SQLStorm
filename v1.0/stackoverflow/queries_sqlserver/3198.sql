
WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        u.DisplayName AS OwnerDisplayName,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpVotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownVotes,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PostRank
    FROM 
        Posts p
    LEFT JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    WHERE 
        p.PostTypeId = 1
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.Score, u.DisplayName
),
RecentComments AS (
    SELECT 
        c.PostId,
        COUNT(c.Id) AS CommentCount,
        MAX(c.CreationDate) AS LastCommentDate
    FROM 
        Comments c
    GROUP BY 
        c.PostId
),
ClosedPosts AS (
    SELECT 
        ph.PostId,
        ph.CreationDate AS ClosedDate,
        clr.Name AS CloseReason
    FROM 
        PostHistory ph
    JOIN 
        CloseReasonTypes clr ON CAST(ph.Comment AS NVARCHAR(MAX)) = CAST(clr.Id AS NVARCHAR(MAX))
    WHERE 
        ph.PostHistoryTypeId = 10
),
FinalResult AS (
    SELECT 
        rp.PostId,
        rp.Title,
        rp.CreationDate AS PostCreationDate,
        rp.Score,
        rp.OwnerDisplayName,
        rp.UpVotes,
        rp.DownVotes,
        COALESCE(rc.CommentCount, 0) AS TotalComments,
        rc.LastCommentDate,
        cp.ClosedDate,
        cp.CloseReason
    FROM 
        RankedPosts rp
    LEFT JOIN 
        RecentComments rc ON rp.PostId = rc.PostId
    LEFT JOIN 
        ClosedPosts cp ON rp.PostId = cp.PostId
    WHERE 
        rp.PostRank = 1
)
SELECT 
    *
FROM 
    FinalResult
ORDER BY 
    Score DESC, PostCreationDate DESC
OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY;

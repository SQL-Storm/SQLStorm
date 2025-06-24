
WITH PostStats AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.CreationDate,
        COALESCE(SUM(v.BountyAmount), 0) AS TotalBounty,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT ph.Id) AS EditCount,
        (SELECT u.DisplayName FROM Users u WHERE u.Id = p.LastEditorUserId ORDER BY p.CreationDate LIMIT 1) AS FirstEditor
    FROM 
        Posts p
        LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId = 8 
        LEFT JOIN Comments c ON p.Id = c.PostId
        LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE 
        p.CreationDate >= '2023-10-01 12:34:56'
        AND p.PostTypeId = 1 
    GROUP BY 
        p.Id, p.Title, p.Score, p.CreationDate
),
RankedPosts AS (
    SELECT 
        ps.PostId,
        ps.Title,
        ps.Score,
        ps.TotalBounty,
        ps.CommentCount,
        ps.EditCount,
        RANK() OVER (ORDER BY ps.Score DESC, ps.TotalBounty DESC) AS PostRank,
        CASE 
            WHEN ps.CommentCount = 0 THEN 'No Comments'
            WHEN ps.CommentCount BETWEEN 1 AND 5 THEN 'Few Comments'
            ELSE 'Many Comments'
        END AS CommentCategory
    FROM 
        PostStats ps
)
SELECT 
    rp.PostId,
    rp.Title,
    rp.Score,
    rp.TotalBounty,
    rp.CommentCount,
    rp.EditCount,
    rp.PostRank,
    rp.CommentCategory,
    CASE 
        WHEN rp.EditCount > 0 THEN 'Edited'
        ELSE 'Not Edited' 
    END AS EditStatus,
    CASE 
        WHEN rp.TotalBounty = 0 THEN 'No Bounty'
        ELSE 'Has Bounty'
    END AS BountyStatus
FROM 
    RankedPosts rp
WHERE 
    rp.PostRank <= 10 
ORDER BY 
    rp.PostRank;

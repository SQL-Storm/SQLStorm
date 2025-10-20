WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.ViewCount,
        p.AnswerCount,
        u.DisplayName AS OwnerDisplayName,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.ViewCount DESC) AS RankByViews
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.CreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
),
PostDetails AS (
    SELECT 
        rp.PostId,
        rp.Title,
        rp.CreationDate,
        rp.ViewCount,
        rp.AnswerCount,
        rp.OwnerDisplayName,
        ph.Comment AS LastEditComment,
        ph.CreationDate AS LastEditDate,
        rp.RankByViews
    FROM 
        RankedPosts rp
    LEFT JOIN 
        PostHistory ph ON rp.PostId = ph.PostId
    WHERE 
        ph.CreationDate = (
            SELECT MAX(ph2.CreationDate) 
            FROM PostHistory ph2 
            WHERE ph2.PostId = rp.PostId
        )
),
AggregateData AS (
    SELECT 
        p.Id AS PostId,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) AS VoteCount
    FROM 
        Posts p
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    GROUP BY 
        p.Id
)
SELECT 
    pd.PostId,
    pd.Title,
    pd.CreationDate,
    pd.ViewCount,
    pd.AnswerCount,
    pd.OwnerDisplayName,
    pd.LastEditComment,
    pd.LastEditDate,
    ag.CommentCount,
    ag.VoteCount
FROM 
    PostDetails pd
JOIN 
    AggregateData ag ON pd.PostId = ag.PostId
WHERE 
    pd.RankByViews <= 10
ORDER BY 
    pd.RankByViews;
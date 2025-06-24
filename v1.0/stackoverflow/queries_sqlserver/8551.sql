
WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.CreationDate,
        p.ViewCount,
        u.DisplayName AS OwnerDisplayName,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS ScoreRank,
        COUNT(c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes
    FROM 
        Posts p
    LEFT JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    WHERE 
        p.CreationDate >= DATEADD(YEAR, -1, '2024-10-01 12:34:56')
    GROUP BY 
        p.Id, p.Title, p.Score, p.CreationDate, p.ViewCount, u.DisplayName, p.PostTypeId
),
PostDetails AS (
    SELECT 
        rp.PostId,
        rp.Title,
        rp.Score,
        rp.CreationDate,
        rp.ViewCount,
        rp.OwnerDisplayName,
        rp.ScoreRank,
        rp.CommentCount,
        rp.Upvotes,
        rp.Downvotes,
        COALESCE(t.TagName, 'No Tags') AS TagName
    FROM 
        RankedPosts rp
    OUTER APPLY (
        SELECT 
            value AS TagName
        FROM 
            STRING_SPLIT(rp.Tags, '><')
    ) t 
    WHERE 
        rp.ScoreRank <= 5
)
SELECT 
    pd.PostId,
    pd.Title,
    pd.Score,
    pd.CreationDate,
    pd.ViewCount,
    pd.OwnerDisplayName,
    pd.CommentCount,
    pd.Upvotes,
    pd.Downvotes,
    STRING_AGG(DISTINCT pd.TagName, ', ') AS Tags
FROM 
    PostDetails pd
GROUP BY 
    pd.PostId, pd.Title, pd.Score, pd.CreationDate, pd.ViewCount, pd.OwnerDisplayName, pd.CommentCount, pd.Upvotes, pd.Downvotes
ORDER BY 
    pd.Score DESC, pd.CreationDate DESC
OFFSET 0 ROWS FETCH NEXT 50 ROWS ONLY;

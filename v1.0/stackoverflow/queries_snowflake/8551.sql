
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
        p.CreationDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year'
    GROUP BY 
        p.Id, u.DisplayName, p.PostTypeId
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
    LEFT JOIN 
        (
            SELECT 
                p.Id AS PostId,
                TRIM(REGEXP_SUBSTR(p.Tags, '[^><]+', 1, seq)) AS TagName
            FROM 
                Posts p,
                (SELECT seq4() AS seq FROM TABLE(GENERATOR(ROWCOUNT => 100))) seqs
            WHERE 
                p.Id = rp.PostId
            AND 
                seq <= REGEXP_COUNT(p.Tags, '><') + 1       
        ) t ON t.PostId = rp.PostId
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
    LISTAGG(DISTINCT pd.TagName, ', ') AS Tags
FROM 
    PostDetails pd
GROUP BY 
    pd.PostId, pd.Title, pd.Score, pd.CreationDate, pd.ViewCount, pd.OwnerDisplayName, pd.CommentCount, pd.Upvotes, pd.Downvotes
ORDER BY 
    pd.Score DESC, pd.CreationDate DESC
LIMIT 50;

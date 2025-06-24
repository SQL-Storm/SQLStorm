WITH RankedPosts AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.Score, 
        p.CreationDate, 
        u.DisplayName AS OwnerDisplayName, 
        p.ViewCount, 
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate DESC) as Rank
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.CreationDate >= NOW() - interval '1 year' 
        AND p.Score > 0
), 
TopPosts AS (
    SELECT 
        rp.Id, 
        rp.Title, 
        rp.OwnerDisplayName, 
        rp.Score, 
        rp.ViewCount
    FROM 
        RankedPosts rp
    WHERE 
        rp.Rank <= 10
), 
PostWithComments AS (
    SELECT 
        tp.Id AS PostId,
        tp.Title,
        tp.OwnerDisplayName,
        tp.Score,
        COUNT(c.Id) AS CommentCount
    FROM 
        TopPosts tp
    LEFT JOIN 
        Comments c ON tp.Id = c.PostId
    GROUP BY 
        tp.Id, tp.Title, tp.OwnerDisplayName, tp.Score
)
SELECT 
    pwc.PostId,
    pwc.Title,
    pwc.OwnerDisplayName,
    pwc.Score,
    pwc.CommentCount,
    (SELECT 
        AVG(VoteTypeId = 2) 
     FROM 
        Votes v 
     WHERE 
        v.PostId = pwc.PostId) AS AverageUpVotes,
    (SELECT 
        COUNT(*) 
     FROM 
        PostHistory ph 
     WHERE 
        ph.PostId = pwc.PostId) AS EditCount
FROM 
    PostWithComments pwc
ORDER BY 
    pwc.Score DESC, pwc.CommentCount DESC;

WITH RankedPosts AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.CreationDate, 
        p.Score, 
        p.ViewCount, 
        u.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS PostRank
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.PostTypeId = 1 AND -- Only Questions
        p.CreationDate >= NOW() - INTERVAL '1 year' -- Last year
),
TopPosts AS (
    SELECT 
        Id, 
        Title, 
        CreationDate, 
        Score, 
        ViewCount, 
        OwnerDisplayName
    FROM 
        RankedPosts
    WHERE 
        PostRank <= 5 -- Top 5 questions per user
),
PostVotes AS (
    SELECT 
        PostId, 
        COUNT(*) AS VoteCount
    FROM 
        Votes
    WHERE 
        VoteTypeId IN (2, 3) -- Upvotes and Downvotes
    GROUP BY 
        PostId
),
PostComments AS (
    SELECT 
        PostId, 
        COUNT(*) AS CommentCount
    FROM 
        Comments
    GROUP BY 
        PostId
)
SELECT 
    tp.Title, 
    tp.CreationDate, 
    tp.OwnerDisplayName, 
    COALESCE(pv.VoteCount, 0) AS VoteCount, 
    COALESCE(pc.CommentCount, 0) AS CommentCount, 
    tp.Score, 
    tp.ViewCount
FROM 
    TopPosts tp
LEFT JOIN 
    PostVotes pv ON tp.Id = pv.PostId
LEFT JOIN 
    PostComments pc ON tp.Id = pc.PostId
ORDER BY 
    tp.Score DESC, 
    tp.CreationDate DESC;

-- {"query": "1051.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 490} 
WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS rn,
        u.DisplayName AS OwnerDisplayName,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVoteCount
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.PostTypeId = 1 AND -- Only questions
        p.CreationDate >= '2023-01-01' -- Posts created in 2023
),
TopPosts AS (
    SELECT 
        rp.PostId,
        rp.Title,
        rp.CreationDate,
        rp.Score,
        rp.ViewCount,
        rp.CommentCount,
        rp.UpVoteCount,
        rp.OwnerDisplayName
    FROM 
        RankedPosts rp
    WHERE 
        rp.rn = 1 -- Get the top post per user
)
SELECT 
    tp.Title,
    tp.CreationDate,
    tp.ViewCount,
    COALESCE(tp.CommentCount, 0) AS CommentCount,
    COALESCE(tp.UpVoteCount, 0) AS UpVoteCount,
    (SELECT 
        STRING_AGG(b.Name, ', ') 
     FROM 
        Badges b 
     WHERE 
        b.UserId = (SELECT OwnerUserId FROM Posts WHERE Id = tp.PostId)) AS UserBadges,
    CASE 
        WHEN tp.ViewCount > 100 THEN 'High Engagement'
        WHEN tp.ViewCount > 50 THEN 'Medium Engagement'
        ELSE 'Low Engagement'
    END AS EngagementLevel
FROM 
    TopPosts tp
LEFT JOIN 
    PostHistory ph ON tp.PostId = ph.PostId AND ph.PostHistoryTypeId IN (10, 11) -- Closed and reopened
LEFT JOIN 
    CloseReasonTypes crt ON CAST(ph.Comment AS INT) = crt.Id -- Get close reason if applicable
WHERE 
    ph.Id IS NULL -- Ensure post is not closed
ORDER BY 
    tp.ViewCount DESC
LIMIT 10;
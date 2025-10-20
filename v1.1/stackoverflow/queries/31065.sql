WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        COUNT(c.Id) AS CommentCount,
        COUNT(v.Id) AS VoteCount,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate DESC) AS Rank
    FROM 
        Posts p
    LEFT JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    WHERE 
        p.PostTypeId IN (1, 2) -- Only Questions and Answers
    GROUP BY 
        p.Id, p.Title, u.DisplayName, p.CreationDate, p.Score, p.ViewCount, p.PostTypeId
),
MostCommented AS (
    SELECT 
        PostId,
        Title,
        OwnerDisplayName,
        CreationDate,
        Score,
        ViewCount,
        CommentCount,
        VoteCount
    FROM 
        RankedPosts
    WHERE 
        Rank <= 5 -- Top 5 posts per type based on Score
),
PostHistoryAggregation AS (
    SELECT 
        ph.PostId,
        ph.PostHistoryTypeId,
        COUNT(*) AS ChangeCount
    FROM 
        PostHistory ph
    WHERE 
        ph.CreationDate > (CAST('2024-10-01' AS DATE) - INTERVAL '1' YEAR)
    GROUP BY 
        ph.PostId, ph.PostHistoryTypeId
)
SELECT 
    m.PostId,
    m.Title,
    m.OwnerDisplayName,
    m.CreationDate,
    m.Score,
    m.ViewCount,
    m.CommentCount,
    m.VoteCount,
    ph.ChangeCount
FROM 
    MostCommented m
LEFT JOIN 
    PostHistoryAggregation ph ON m.PostId = ph.PostId
ORDER BY 
    m.CommentCount DESC, m.Score DESC;
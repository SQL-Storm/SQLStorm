-- {"query": "1086.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 568} 

WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn,
        COUNT(c.Id) AS CommentCount,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpvoteCount,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownvoteCount
    FROM 
        Posts p
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount
),
TagCounts AS (
    SELECT 
        p.Id AS PostId,
        COUNT(DISTINCT t.Id) AS TagCount
    FROM 
        Posts p
    LEFT JOIN 
        Tags t ON POSITION('"' || t.TagName || '"' IN p.Tags) > 0
    GROUP BY 
        p.Id
)
SELECT 
    rp.PostId,
    rp.Title,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.CommentCount,
    rp.UpvoteCount,
    rp.DownvoteCount,
    tc.TagCount,
    CASE 
        WHEN rp.Score > 0 THEN 'Positive'
        WHEN rp.Score = 0 THEN 'Neutral'
        ELSE 'Negative'
    END AS ScoreCategory
FROM 
    RankedPosts rp
JOIN 
    TagCounts tc ON rp.PostId = tc.PostId
WHERE 
    rp.rn <= 10
ORDER BY 
    rp.CreationDate DESC, rp.Score DESC
UNION ALL
SELECT 
    CAST(NULL AS INT) AS PostId,
    'Total Posts' AS Title,
    NULL AS CreationDate,
    NULL AS Score,
    NULL AS ViewCount,
    SUM(CommentCount) AS CommentCount,
    SUM(UpvoteCount) AS UpvoteCount,
    SUM(DownvoteCount) AS DownvoteCount,
    SUM(TagCount) AS TagCount,
    NULL AS ScoreCategory
FROM 
    (
        SELECT 
            COUNT(CommentCount) AS CommentCount,
            COUNT(UpvoteCount) AS UpvoteCount,
            COUNT(DownvoteCount) AS DownvoteCount,
            COUNT(TagCount) AS TagCount
        FROM 
            RankedPosts rp
        JOIN 
            TagCounts tc ON rp.PostId = tc.PostId
    ) AS Summary
;

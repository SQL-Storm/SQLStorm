WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Body,
        p.Tags,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate,
        p.LastActivityDate,
        p.Score,
        p.ViewCount,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS rn
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.CreationDate >= NOW() - INTERVAL '1 year'
        AND p.PostTypeId IN (1, 2) -- Considering Questions and Answers only
),
TopPosts AS (
    SELECT 
        rp.PostId,
        rp.Title,
        rp.OwnerDisplayName,
        rp.Score,
        rp.ViewCount,
        rp.Tags,
        rp.CreationDate,
        rp.LastActivityDate
    FROM 
        RankedPosts rp
    WHERE 
        rp.rn <= 10 -- Top 10 posts of each type
),
TagOccurrences AS (
    SELECT 
        UNNEST(string_to_array(Tags, '>')) AS Tag
    FROM 
        TopPosts
),
TagCounts AS (
    SELECT 
        Tag,
        COUNT(*) AS OccurrenceCount
    FROM 
        TagOccurrences
    GROUP BY 
        Tag
    ORDER BY 
        OccurrenceCount DESC
    LIMIT 5 -- Top 5 Tags
)
SELECT 
    tp.Title,
    tp.OwnerDisplayName,
    tp.Score,
    tp.ViewCount,
    tc.Tag,
    tc.OccurrenceCount
FROM 
    TopPosts tp
JOIN 
    TagCounts tc ON tp.Tags LIKE '%' || tc.Tag || '%' -- Get posts that contain these tags
ORDER BY 
    tp.Score DESC, 
    tp.ViewCount DESC;

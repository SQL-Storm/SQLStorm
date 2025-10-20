WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId, 
        p.Title, 
        p.CreationDate, 
        u.DisplayName AS OwnerDisplayName, 
        COUNT(c.Id) AS CommentCount,
        COUNT(v.Id) AS VoteCount,
        ROW_NUMBER() OVER(PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate DESC) AS RankByScore
    FROM 
        Posts p
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    LEFT JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
    GROUP BY 
        p.Id, p.Title, p.CreationDate, u.DisplayName, p.PostTypeId, p.Score
),
TopPosts AS (
    SELECT 
        PostId, 
        Title, 
        CreationDate, 
        OwnerDisplayName, 
        CommentCount, 
        VoteCount
    FROM 
        RankedPosts
    WHERE 
        RankByScore <= 10
),
PostTags AS (
    -- split tags stored as comma-separated string in Posts.Tags into rows
    SELECT
        p.Id AS PostId,
        TRIM(tag) AS TagName
    FROM Posts p
    CROSS JOIN LATERAL (
        SELECT value
        FROM (
            SELECT
                -- replace support for various dialects: split string into rows
                -- use regexp_split_to_table if available, else emulate with string functions
                -- here we use standard SQL: simulate with UNNEST on STRING_TO_ARRAY if present,
                -- but to maximize compatibility, use a common approach with regexp_split_to_table when possible.
                regexp_split_to_table(p.Tags, E',') AS value
        ) s
    ) split(tag)
),
TagCounts AS (
    SELECT
        t.TagName,
        COUNT(*) AS Count
    FROM PostTags pt
    JOIN Tags t ON pt.TagName = t.TagName
    GROUP BY t.TagName
)
SELECT 
    tp.PostId, 
    tp.Title, 
    tp.CreationDate, 
    tp.OwnerDisplayName, 
    tp.CommentCount, 
    tp.VoteCount,
    COALESCE(pt.TagName, t.TagName) AS TagName,
    COALESCE(tc.Count, 0) AS TagUsageCount
FROM 
    TopPosts tp
LEFT JOIN 
    PostTags pt ON tp.PostId = pt.PostId
LEFT JOIN 
    Tags t ON pt.TagName = t.TagName
LEFT JOIN
    TagCounts tc ON COALESCE(pt.TagName, t.TagName) = tc.TagName
GROUP BY
    tp.PostId, tp.Title, tp.CreationDate, tp.OwnerDisplayName, tp.CommentCount, tp.VoteCount, pt.TagName, t.TagName, tc.Count
ORDER BY 
    tp.VoteCount DESC, tp.CommentCount DESC;
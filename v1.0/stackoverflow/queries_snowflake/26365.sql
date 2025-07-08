
WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Body,
        p.Tags,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate,
        p.ViewCount,
        p.Score,
        p.AnswerCount,
        ROW_NUMBER() OVER (PARTITION BY p.Tags ORDER BY p.ViewCount DESC, p.CreationDate DESC) AS TagRank
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.PostTypeId = 1 
        AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year') 
),
FilteredTags AS (
    SELECT 
        TRIM(BOTH '<>' FROM tag) AS Tag
    FROM (
        SELECT 
            FLATTEN(input => STRING_SPLIT(TRIM(BOTH '<>' FROM Tags), '><')) AS tag
        FROM 
            RankedPosts
    )
    GROUP BY 
        Tag
    HAVING 
        COUNT(*) > 10 
),
TopPosts AS (
    SELECT 
        rp.*
    FROM 
        RankedPosts rp
    JOIN 
        FilteredTags ft ON position(ft.Tag IN rp.Tags) > 0
    WHERE 
        rp.TagRank <= 5 
)
SELECT 
    tp.OwnerDisplayName,
    tp.Title,
    tp.CreationDate,
    tp.ViewCount,
    tp.Score,
    tp.AnswerCount
FROM 
    TopPosts tp
ORDER BY 
    tp.ViewCount DESC, tp.CreationDate DESC
LIMIT 50;

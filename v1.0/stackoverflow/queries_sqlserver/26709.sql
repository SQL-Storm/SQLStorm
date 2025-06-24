
WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        u.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY SUBSTRING(Tags, 2, LEN(Tags) - 2) ORDER BY p.Score DESC, p.ViewCount DESC) AS Rank
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.PostTypeId = 1  
),
PopularTags AS (
    SELECT 
        value AS Tag
    FROM 
        STRING_SPLIT(SUBSTRING(Tags, 2, LEN(Tags) - 2), '> <')
    WHERE 
        PostTypeId = 1
),
TagCounts AS (
    SELECT 
        Tag,
        COUNT(*) AS TagCount
    FROM 
        PopularTags
    GROUP BY 
        Tag
    ORDER BY 
        TagCount DESC
)
SELECT TOP 10
    rp.PostId,
    rp.Title,
    rp.Tags,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.OwnerDisplayName,
    tc.Tag AS PopularTag,
    tc.TagCount
FROM 
    RankedPosts rp
JOIN 
    TagCounts tc ON rp.Tags LIKE '%' + tc.Tag + '%'
WHERE 
    rp.Rank <= 5  
ORDER BY 
    tc.TagCount DESC, rp.Score DESC;

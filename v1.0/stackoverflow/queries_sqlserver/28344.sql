
WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Tags,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY p.Tags ORDER BY p.Score DESC) AS TagRank
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.PostTypeId = 1 
),
FilteredPosts AS (
    SELECT 
        rp.PostId,
        rp.Title,
        rp.Tags,
        rp.OwnerDisplayName,
        rp.CreationDate,
        rp.Score
    FROM 
        RankedPosts rp
    WHERE 
        rp.TagRank <= 5 
),
PopularTags AS (
    SELECT 
        value AS TagName
    FROM 
        FilteredPosts f
    CROSS APPLY STRING_SPLIT(f.Tags, ',')
),
TagFrequency AS (
    SELECT 
        TagName,
        COUNT(*) AS PostCount
    FROM 
        PopularTags
    GROUP BY 
        TagName
    ORDER BY 
        PostCount DESC
)
SELECT TOP 10
    tf.TagName,
    fp.PostId,
    fp.Title,
    fp.OwnerDisplayName,
    fp.CreationDate,
    fp.Score
FROM 
    TagFrequency tf
JOIN 
    FilteredPosts fp ON tf.TagName = TRIM(value)
    CROSS APPLY STRING_SPLIT(fp.Tags, ',')
ORDER BY 
    tf.PostCount DESC, 
    fp.Score DESC;

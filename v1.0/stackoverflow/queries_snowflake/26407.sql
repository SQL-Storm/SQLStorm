
WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Body,
        p.Tags,
        u.DisplayName AS Author,
        p.CreationDate,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY p.Tags ORDER BY p.CreationDate DESC) AS rn
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.PostTypeId = 1  
        AND p.Body IS NOT NULL
),
TagCount AS (
    SELECT 
        TRIM(value) AS Tag,
        COUNT(*) AS Count
    FROM 
        Posts,
        LATERAL SPLIT_TO_ARRAY(SUBSTRING(Tags, 2, CHAR_LENGTH(Tags) - 2), '><') AS value
    WHERE 
        PostTypeId = 1
    GROUP BY 
        Tag
),
TopTags AS (
    SELECT 
        Tag,
        Count
    FROM 
        TagCount
    ORDER BY 
        Count DESC
    LIMIT 10
),
PostHistoryDismissed AS (
    SELECT 
        ph.PostId,
        LISTAGG(DISTINCT pht.Name, ', ') AS DismissedHistory
    FROM 
        PostHistory ph
    JOIN 
        PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    WHERE 
        pht.Name IN ('Post Deleted', 'Post Closed', 'Post Undeleted')
    GROUP BY 
        ph.PostId
)
SELECT 
    rp.PostId,
    rp.Title,
    rp.Body,
    rp.Tags,
    rp.Author,
    rp.CreationDate,
    rp.Score,
    th.DismissedHistory,
    tt.Tag AS TopTag
FROM 
    RankedPosts rp
LEFT JOIN 
    PostHistoryDismissed th ON rp.PostId = th.PostId
JOIN 
    TopTags tt ON POSITION(tt.Tag IN rp.Tags) > 0
WHERE 
    rp.rn = 1  
ORDER BY 
    rp.CreationDate DESC;

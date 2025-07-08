
WITH RankedPosts AS (
    SELECT 
        p.Id AS PostID,
        p.Title,
        p.CreationDate,
        p.ViewCount,
        p.Score,
        u.DisplayName AS OwnerDisplayName,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY 
            CASE 
                WHEN p.PostTypeId = 1 THEN 'Question'
                WHEN p.PostTypeId = 2 THEN 'Answer'
                ELSE 'Other'
            END 
            ORDER BY p.Score DESC) AS Rank
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.CreationDate >= DATEADD(year, -1, CURRENT_DATE())
        AND p.ViewCount > 100
),
TagStats AS (
    SELECT 
        TRIM(BOTH '<>' FROM value) AS Tag,
        COUNT(*) AS PostCount
    FROM 
        Posts p,
        LATERAL FLATTEN(input => SPLIT(p.Tags, '><')) 
    WHERE 
        p.PostTypeId = 1
    GROUP BY 
        Tag
),
TopTags AS (
    SELECT 
        Tag,
        PostCount,
        ROW_NUMBER() OVER (ORDER BY PostCount DESC) AS TagRank
    FROM 
        TagStats
    WHERE 
        PostCount > 5 
),
TopPostsByTag AS (
    SELECT 
        rp.PostID,
        rp.Title,
        rp.OwnerDisplayName,
        rp.Rank,
        rt.Tag
    FROM 
        RankedPosts rp
    JOIN 
        Posts p ON rp.PostID = p.Id
    JOIN 
        LATERAL FLATTEN(input => SPLIT(p.Tags, '><')) AS rt ON TRUE
    JOIN 
        TopTags tt ON rt.value = tt.Tag
    WHERE 
        rp.Rank <= 5 
)
SELECT 
    t.Tag,
    LISTAGG(tp.OwnerDisplayName || ': ' || tp.Title, '; ') AS TopPosts
FROM 
    TopPostsByTag tp
JOIN 
    TopTags t ON tp.Tag = t.Tag
GROUP BY 
    t.Tag
ORDER BY 
    t.Tag;

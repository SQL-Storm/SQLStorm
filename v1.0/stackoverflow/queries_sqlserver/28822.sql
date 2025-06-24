
WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.ViewCount,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY p.Tags ORDER BY p.Score DESC) AS TagRank
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 1 
),
FilteredTags AS (
    SELECT 
        LTRIM(RTRIM(REPLACE(REPLACE(value, '<', ''), '>', ''))) AS TagName,
        COUNT(*) AS PostCount
    FROM 
        RankedPosts
        CROSS APPLY STRING_SPLIT(SUBSTRING(Tags, 2, LEN(Tags)-2), '><') 
    WHERE 
        TagRank <= 5 
    GROUP BY 
        TagName
),
TopTags AS (
    SELECT 
        TagName,
        PostCount,
        RANK() OVER (ORDER BY PostCount DESC) AS TagPopularity
    FROM 
        FilteredTags
)
SELECT 
    tt.TagName,
    tt.PostCount,
    p.Title,
    p.Score,
    u.DisplayName AS UserCreator,
    p.CreationDate
FROM 
    TopTags tt
JOIN 
    Posts p ON tt.TagName IN (SELECT value FROM STRING_SPLIT(SUBSTRING(p.Tags, 2, LEN(p.Tags)-2), '><'))
JOIN 
    Users u ON p.OwnerUserId = u.Id
WHERE 
    tt.TagPopularity <= 10 
ORDER BY 
    tt.PostCount DESC, p.Score DESC;

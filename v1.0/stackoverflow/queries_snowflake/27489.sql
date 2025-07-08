
WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Body,
        p.CreationDate,
        p.ViewCount,
        p.Score,
        p.Tags,
        SIZE(SPLIT(REPLACE(p.Tags, '>', ''), ',')) AS TagCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PostRank,
        u.Reputation AS UserReputation,
        u.DisplayName AS UserDisplayName
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.PostTypeId = 1 AND 
        p.CreationDate >= DATEADD(DAY, -30, '2024-10-01 12:34:56'::TIMESTAMP) 
),
TopTags AS (
    SELECT 
        VALUE AS TagName,
        COUNT(*) AS TagUsage
    FROM 
        Posts p,
        LATERAL FLATTEN(INPUT => SPLIT(REPLACE(p.Tags, '>', ''), ',')) AS Tag
    WHERE 
        p.PostTypeId = 1 AND 
        p.CreationDate >= DATEADD(DAY, -30, '2024-10-01 12:34:56'::TIMESTAMP)
    GROUP BY 
        TagName
    ORDER BY 
        TagUsage DESC
    LIMIT 10
),
PostComments AS (
    SELECT 
        c.PostId,
        COUNT(c.Id) AS CommentCount,
        LISTAGG(DISTINCT c.UserDisplayName, ', ') AS CommentAuthors
    FROM 
        Comments c
    GROUP BY 
        c.PostId
)
SELECT 
    r.PostId,
    r.Title,
    r.Body,
    r.CreationDate,
    r.ViewCount,
    r.Score,
    r.TagCount,
    r.UserReputation,
    r.UserDisplayName,
    pc.CommentCount,
    pc.CommentAuthors,
    tt.TagName AS PopularTag,
    tt.TagUsage AS TagUsageCount
FROM 
    RankedPosts r
LEFT JOIN 
    PostComments pc ON r.PostId = pc.PostId
LEFT JOIN 
    TopTags tt ON tt.TagName IN (SELECT VALUE FROM LATERAL FLATTEN(INPUT => SPLIT(REPLACE(r.Tags, '>', ''), ',')))
WHERE 
    r.PostRank = 1 
ORDER BY 
    r.Score DESC, r.ViewCount DESC;

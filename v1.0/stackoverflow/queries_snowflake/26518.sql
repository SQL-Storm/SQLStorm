
WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Tags,
        u.DisplayName AS OwnerDisplayName,
        COUNT(c.Id) AS CommentCount,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY p.CreationDate DESC) AS Rank
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    WHERE 
        p.PostTypeId = 1 
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.Tags, u.DisplayName
),

TagStats AS (
    SELECT 
        TRIM(tag) AS TagName,
        COUNT(*) AS PostCount
    FROM 
        Posts,
        LATERAL SPLIT_TO_TABLE(SUBSTRING(Tags, 2, LENGTH(Tags) - 2), '><') AS tag
    WHERE 
        PostTypeId = 1
    GROUP BY 
        TagName
    ORDER BY 
        PostCount DESC
    LIMIT 10
)

SELECT 
    rp.PostId,
    rp.Title,
    rp.CreationDate,
    rp.OwnerDisplayName,
    rp.CommentCount,
    ts.TagName,
    ts.PostCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = rp.PostId AND v.VoteTypeId = 2) AS UpVotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = rp.PostId AND v.VoteTypeId = 3) AS DownVotes
FROM 
    RankedPosts rp
JOIN 
    TagStats ts ON ts.TagName = ANY(ARRAY_CONSTRUCT(TRIM(tag)) FROM LATERAL SPLIT_TO_TABLE(SUBSTRING(rp.Tags, 2, LENGTH(rp.Tags) - 2), '><')))
WHERE 
    rp.Rank = 1 
ORDER BY 
    rp.CreationDate DESC;


WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Body,
        p.Tags,
        p.CreationDate,
        u.DisplayName AS Author,
        COUNT(c.Id) AS CommentCount,
        COUNT(v.Id) AS VoteCount,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY p.CreationDate DESC) AS rn
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    WHERE 
        p.PostTypeId = 1  
    GROUP BY 
        p.Id, u.DisplayName, p.Title, p.Body, p.Tags, p.CreationDate
),

PopularTags AS (
    SELECT 
        TRIM(tag) AS TagName,
        COUNT(*) AS TagCount
    FROM 
        Posts p,
        LATERAL FLATTEN(input => SPLIT(SUBSTR(p.Tags, 2, LENGTH(p.Tags) - 2), '><')) AS tag
    WHERE 
        p.PostTypeId = 1  
    GROUP BY 
        TagName
    ORDER BY 
        TagCount DESC
    LIMIT 10
),

PostHistorySummary AS (
    SELECT 
        ph.PostId,
        COUNT(*) AS EditCount,
        MAX(ph.CreationDate) AS LastEditDate
    FROM 
        PostHistory ph
    GROUP BY 
        ph.PostId
)

SELECT 
    rp.PostId,
    rp.Title,
    rp.Body,
    rp.Tags,
    rp.CreationDate,
    rp.Author,
    rp.CommentCount,
    rp.VoteCount,
    pts.EditCount,
    pts.LastEditDate,
    pt.TagName
FROM 
    RankedPosts rp
JOIN 
    PostHistorySummary pts ON rp.PostId = pts.PostId
JOIN 
    PopularTags pt ON pt.TagName IN (TRIM(tag) FROM SPLIT(SUBSTR(rp.Tags, 2, LENGTH(rp.Tags) - 2), '><'))
ORDER BY 
    rp.VoteCount DESC, rp.CommentCount DESC;

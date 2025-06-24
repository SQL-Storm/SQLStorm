WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Body,
        p.Tags,
        p.CreationDate,
        u.DisplayName AS OwnerDisplayName,
        COUNT(DISTINCT a.Id) AS AnswerCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COALESCE(ROUND(AVG(v.VoteTypeId = 2) * 100.0 / NULLIF(COUNT(v.Id), 0), 2), 0) AS UpvotePercentage,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY p.CreationDate DESC) AS rn
    FROM 
        Posts p
    LEFT JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
    LEFT JOIN 
        Comments c ON c.PostId = p.Id
    LEFT JOIN 
        Votes v ON v.PostId = p.Id
    WHERE 
        p.PostTypeId = 1 -- Only questions
    GROUP BY 
        p.Id, p.Title, p.Body, p.Tags, p.CreationDate, u.DisplayName
), 

TagStats AS (
    SELECT 
        UNNEST(string_to_array(Tags, '><')) AS TagName,
        COUNT(*) AS PostCount,
        AVG(EXTRACT(EPOCH FROM NOW() - CreationDate)) AS AvgTimeSinceLastPost
    FROM 
        Posts
    WHERE 
        PostTypeId = 1 -- Only questions
    GROUP BY 
        TagName
),

PopularTags AS (
    SELECT 
        ts.TagName,
        ts.PostCount,
        ts.AvgTimeSinceLastPost,
        lt.Name AS LinkTypeName
    FROM 
        TagStats ts
    LEFT JOIN 
        LinkTypes lt ON ts.TagName LIKE '%' || lt.Name || '%' -- Example logic for linking tag names to link types
    ORDER BY 
        ts.PostCount DESC
    LIMIT 10
)

SELECT 
    rp.PostId,
    rp.Title,
    rp.OwnerDisplayName,
    rp.CreationDate,
    rp.AnswerCount,
    rp.CommentCount,
    rp.UpvotePercentage,
    pt.TagName,
    pt.PostCount AS TagPostCount,
    pt.AvgTimeSinceLastPost
FROM 
    RankedPosts rp
LEFT JOIN 
    PopularTags pt ON rp.Tags LIKE '%' || pt.TagName || '%'
WHERE 
    rp.rn = 1 -- Get the most recent post per unique post ID
ORDER BY 
    rp.CreationDate DESC;

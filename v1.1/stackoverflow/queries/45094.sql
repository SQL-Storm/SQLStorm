WITH RankedPosts AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.Score, 
        p.ViewCount,
        p.AnswerCount,
        u.DisplayName,
        u.Reputation,
        DENSE_RANK() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS PostRank,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.CreationDate) AS UserPostSequence
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.PostTypeId = 1 
        AND p.ClosedDate IS NULL
        AND p.Score > 10
        AND p.CreationDate > DATE '2018-01-01'
), 
ExplodedTagsBase AS (
    SELECT
        p.Id AS PostId,
        CASE
            WHEN p.Tags IS NULL THEN NULL
            WHEN LEFT(p.Tags,1) = '<' AND RIGHT(p.Tags,1) = '>' THEN SUBSTRING(p.Tags FROM 2 FOR (CHAR_LENGTH(p.Tags) - 2))
            ELSE p.Tags
        END AS TagsStr
    FROM Posts p
),
ExplodedTags AS (
    -- iterative splitting using a recursive CTE without casting syntax (::)
    WITH RECURSIVE splitter(postid, rest, tag, pos) AS (
        SELECT
            eb.PostId,
            eb.TagsStr,
            CASE
                WHEN eb.TagsStr IS NULL THEN NULL
                WHEN POSITION('><' IN eb.TagsStr) > 0 THEN SUBSTRING(eb.TagsStr FROM 1 FOR POSITION('><' IN eb.TagsStr) - 1)
                ELSE eb.TagsStr
            END,
            1
        FROM ExplodedTagsBase eb
        UNION ALL
        SELECT
            s.postid,
            CASE
                WHEN POSITION('><' IN s.rest) > 0 THEN SUBSTRING(s.rest FROM POSITION('><' IN s.rest) + 2)
                ELSE NULL
            END,
            CASE
                WHEN POSITION('><' IN s.rest) > 0 THEN SUBSTRING(s.rest FROM 1 FOR POSITION('><' IN s.rest) - 1)
                ELSE NULL
            END,
            s.pos + 1
        FROM splitter s
        WHERE s.rest IS NOT NULL AND s.pos <= 1000
    )
    SELECT postid AS PostId, TRIM(tag) AS TagName
    FROM splitter
    WHERE tag IS NOT NULL
),
TagAnalysis AS (
    SELECT 
        et.TagName, 
        COUNT(DISTINCT p.Id) AS TagPostCount,
        AVG(p.Score) AS AvgTagScore,
        MAX(p.ViewCount) AS MaxTagViewCount
    FROM 
        Posts p
    JOIN
        ExplodedTags et ON p.Id = et.PostId
    GROUP BY 
        et.TagName
)
SELECT 
    rp.Id,
    rp.Title,
    rp.Score,
    rp.ViewCount,
    rp.DisplayName,
    rp.Reputation,
    rp.PostRank,
    rp.UserPostSequence,
    ta.TagName,
    ta.TagPostCount,
    ta.AvgTagScore,
    ta.MaxTagViewCount
FROM 
    RankedPosts rp
JOIN 
    Posts p ON rp.Id = p.Id
JOIN
    ExplodedTags et ON p.Id = et.PostId
JOIN 
    TagAnalysis ta ON et.TagName = ta.TagName
WHERE 
    rp.PostRank <= 100
    AND ta.TagPostCount > 50
ORDER BY 
    rp.PostRank, 
    ta.TagPostCount DESC
LIMIT 1000;
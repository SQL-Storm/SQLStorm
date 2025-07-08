
WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Body,
        p.Tags,
        p.CreationDate,
        p.ViewCount,
        p.AnswerCount,
        COALESCE(u.DisplayName, 'Community User') AS OwnerDisplayName,
        ROW_NUMBER() OVER(PARTITION BY p.Tags ORDER BY p.ViewCount DESC) AS TagRank
    FROM 
        Posts p
    LEFT JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.PostTypeId = 1 
        AND p.CreationDate >= DATEADD(year, -1, CURRENT_DATE)
),
PopularTags AS (
    SELECT 
        TRIM(SUBSTRING(value, 2, LENGTH(value) - 2)) AS TagName
    FROM 
        RankedPosts,
        TABLE(FLATTEN(INPUT => SPLIT(Tags, '>'))) AS value
    GROUP BY 
        TRIM(SUBSTRING(value, 2, LENGTH(value) - 2))
),
PostsWithMostAnswers AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        COUNT(a.Id) AS TotalAnswers
    FROM 
        Posts p
    LEFT JOIN 
        Posts a ON p.Id = a.ParentId
    WHERE 
        p.PostTypeId = 1 
    GROUP BY 
        p.Id, p.Title
)
SELECT 
    pt.TagName,
    COUNT(DISTINCT rp.PostId) AS QuestionCount,
    COALESCE(SUM(pma.TotalAnswers), 0) AS TotalAnswers,
    AVG(rp.ViewCount) AS AvgViewCount,
    AVG(DATEDIFF(second, rp.CreationDate, CURRENT_TIMESTAMP) / 60.0) AS AvgTimeSinceCreation
FROM 
    PopularTags pt
JOIN 
    RankedPosts rp ON rp.Tags LIKE '%' || pt.TagName || '%' 
LEFT JOIN 
    PostsWithMostAnswers pma ON rp.PostId = pma.PostId
WHERE 
    rp.TagRank <= 5 
GROUP BY 
    pt.TagName
ORDER BY 
    QuestionCount DESC, TotalAnswers DESC;

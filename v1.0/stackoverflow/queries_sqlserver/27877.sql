
WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Body,
        p.Tags,
        u.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY p.Tags ORDER BY p.CreationDate DESC) AS rn,
        COALESCE(NULLIF(DATALENGTH(p.Body), 0), 1) AS BodyLength
    FROM 
        Posts p
        JOIN Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.PostTypeId = 1 
        AND p.ViewCount > 100 
),
TagStatistics AS (
    SELECT 
        value AS TagName,
        COUNT(*) AS QuestionCount,
        SUM(BodyLength) AS TotalBodyLength,
        AVG(BodyLength) AS AvgBodyLength
    FROM 
        RankedPosts
    CROSS APPLY STRING_SPLIT(SUBSTRING(Tags, 2, LEN(Tags)-2), '><') 
    WHERE 
        rn = 1
    GROUP BY 
        value
),
TopTags AS (
    SELECT 
        TagName,
        QuestionCount,
        TotalBodyLength,
        AvgBodyLength,
        RANK() OVER (ORDER BY QuestionCount DESC) AS TagRank
    FROM 
        TagStatistics
)

SELECT 
    t.TagName,
    t.QuestionCount,
    t.TotalBodyLength,
    t.AvgBodyLength,
    COALESCE(ROUND(CAST(t.TotalBodyLength AS NUMERIC) / NULLIF(t.QuestionCount, 0), 2), 0) AS AvgBodyLengthPerQuestion
FROM 
    TopTags t
WHERE 
    t.TagRank <= 5 
ORDER BY 
    t.TagRank;

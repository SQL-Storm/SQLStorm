
WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Body,
        p.CreationDate,
        u.DisplayName AS Owner,
        p.Score,
        p.ViewCount,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS RowNum
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.PostTypeId = 1  
),
TagStats AS (
    SELECT 
        TRIM(value) AS Tag,
        COUNT(*) AS PostCount
    FROM 
        Posts,
        LATERAL FLATTEN(input => SPLIT(SUBSTRING(Tags, 2, LENGTH(Tags) - 2), '><')) AS value
    WHERE 
        PostTypeId = 1  
    GROUP BY 
        Tag
),
TopUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(*) AS QuestionCount,
        SUM(p.ViewCount) AS TotalViews,
        SUM(p.Score) AS TotalScore
    FROM 
        Users u
    JOIN 
        Posts p ON u.Id = p.OwnerUserId
    WHERE 
        p.PostTypeId = 1  
    GROUP BY 
        u.Id, u.DisplayName
    ORDER BY 
        QuestionCount DESC
    LIMIT 10
),
CombinedStats AS (
    SELECT 
        ru.Owner,
        ru.PostId,
        ru.Title,
        ru.CreationDate,
        ru.Score AS QuestionScore,
        ts.PostCount AS TagCount,
        tu.QuestionCount AS UserQuestionCount,
        tu.TotalViews,
        tu.TotalScore
    FROM 
        RankedPosts ru
    LEFT JOIN 
        TagStats ts ON ts.Tag = TRIM(value)
    LEFT JOIN 
        TopUsers tu ON ru.Owner = tu.DisplayName
    , LATERAL FLATTEN(input => SPLIT(SUBSTRING(ru.Tags, 2, LENGTH(ru.Tags) - 2), '><')) AS value
)
SELECT 
    Owner,
    COUNT(PostId) AS TotalPosts,
    AVG(QuestionScore) AS AverageScore,
    COUNT(DISTINCT TagCount) AS TotalUniqueTags,
    SUM(UserQuestionCount) AS TotalQuestionsByUser,
    SUM(TotalViews) AS TotalViewsByUser,
    AVG(TotalScore) AS AverageUserScore
FROM 
    CombinedStats
GROUP BY 
    Owner
ORDER BY 
    TotalPosts DESC
LIMIT 5;

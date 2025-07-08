
WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Body,
        p.CreationDate,
        p.ViewCount,
        p.Score,
        p.Tags,
        u.DisplayName AS OwnerName,
        ROW_NUMBER() OVER (PARTITION BY p.Tags ORDER BY p.Score DESC) AS RankByScore
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.PostTypeId = 1 
        AND p.Score > 0 
),
TagAggregates AS (
    SELECT 
        TRIM(split.value) AS TagName,
        COUNT(*) AS QuestionCount,
        AVG(ViewCount) AS AvgViewCount,
        SUM(Score) AS TotalScore
    FROM 
        RankedPosts,
        LATERAL FLATTEN(INPUT => SPLIT(SUBSTR(Tags, 2, LEN(Tags) - 2), '><')) AS split
    GROUP BY 
        TagName
),
TopTags AS (
    SELECT 
        TagName,
        QuestionCount,
        AvgViewCount,
        TotalScore,
        ROW_NUMBER() OVER (ORDER BY TotalScore DESC) AS Rank
    FROM 
        TagAggregates
    WHERE 
        QuestionCount >= 5 
)
SELECT 
    tt.TagName,
    tt.QuestionCount,
    tt.AvgViewCount,
    tt.TotalScore,
    rp.Title,
    rp.OwnerName,
    rp.CreationDate
FROM 
    TopTags tt
JOIN 
    RankedPosts rp ON rp.Tags LIKE '%' || tt.TagName || '%'
WHERE 
    rp.RankByScore <= 3 
ORDER BY 
    tt.Rank, rp.Score DESC;

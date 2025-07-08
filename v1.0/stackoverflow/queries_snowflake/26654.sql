
WITH RankedPosts AS (
    SELECT 
        P.Id AS PostId,
        P.Title,
        P.Body,
        P.Tags,
        P.CreationDate,
        U.DisplayName AS Author,
        RANK() OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate DESC) AS PostRank,
        LENGTH(P.Body) AS BodyLength
    FROM 
        Posts P
    JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId = 1  
),
ProcessedTags AS (
    SELECT 
        PostId,
        TRIM_VALUE AS Tag
    FROM 
        RankedPosts,
        TABLE(FLATTEN(INPUT => SPLIT(SUBSTRING(Tags, 2, LENGTH(Tags) - 2), '><'))) AS TAGS
    WHERE 
        Tags IS NOT NULL
),
FilteredTags AS (
    SELECT 
        Tag,
        COUNT(*) AS TagUsage
    FROM 
        ProcessedTags
    GROUP BY 
        Tag
    HAVING 
        COUNT(*) > 5  
),
FinalBenchmark AS (
    SELECT 
        RP.PostId,
        RP.Title,
        RP.Author,
        RP.CreationDate,
        RP.BodyLength,
        FT.Tag,
        FT.TagUsage
    FROM 
        RankedPosts RP
    JOIN 
        FilteredTags FT ON RP.PostId IN (
            SELECT PostId 
            FROM ProcessedTags WHERE Tag = FT.Tag
        )
    WHERE 
        RP.PostRank = 1  
)
SELECT 
    *,
    DATEDIFF(SECOND, CreationDate, '2024-10-01 12:34:56'::TIMESTAMP) AS AgeInSeconds
FROM 
    FinalBenchmark
ORDER BY 
    AgeInSeconds DESC, 
    TagUsage DESC
LIMIT 100;

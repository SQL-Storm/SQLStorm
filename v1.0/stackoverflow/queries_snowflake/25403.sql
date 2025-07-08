
WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Body,
        p.Tags,
        p.ViewCount,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS Rank,
        u.DisplayName AS Author,
        u.Reputation
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.PostTypeId = 1 AND  
        p.CreationDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '6 months'
),

TagCounts AS (
    SELECT 
        TRIM(value) AS TagName,
        COUNT(*) AS TagFrequency
    FROM 
        RankedPosts,
        TABLE(FLATTEN(input => SPLIT(Tags, '><'))) AS f
    GROUP BY 
        TRIM(value)
),

FinalResults AS (
    SELECT 
        rp.PostId,
        rp.Title,
        rp.Author,
        rp.Reputation,
        rp.ViewCount,
        rp.Score,
        tc.TagName,
        tc.TagFrequency
    FROM 
        RankedPosts rp
    JOIN 
        TagCounts tc ON POSITION(tc.TagName IN rp.Tags) > 0 
    WHERE 
        rp.Rank <= 5  
)

SELECT 
    fr.PostId,
    fr.Title,
    fr.Author,
    fr.Reputation,
    fr.ViewCount,
    fr.Score,
    fr.TagName,
    fr.TagFrequency
FROM 
    FinalResults fr
ORDER BY 
    fr.Reputation DESC, 
    fr.Score DESC;

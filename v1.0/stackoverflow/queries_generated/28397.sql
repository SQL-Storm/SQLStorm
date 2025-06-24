WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.ViewCount,
        p.Score,
        p.Tags,
        u.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS Rank
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.PostTypeId = 1  -- Only Questions
        AND p.ViewCount > 100  -- Filter to those with more than 100 views
),
TagStats AS (
    SELECT 
        TAG,
        COUNT(*) AS PostCount,
        SUM(p.Score) AS TotalScore,
        AVG(p.Score) AS AverageScore
    FROM (
        SELECT 
            unnest(string_to_array(TRIM(BOTH '<>' FROM Tags), '>')) AS TAG,
            Score
        FROM 
            Posts
        WHERE 
            PostTypeId = 1  -- Only Questions
    ) AS p
    GROUP BY TAG
),
TopTags AS (
    SELECT 
        TAG,
        PostCount,
        TotalScore,
        AverageScore,
        ROW_NUMBER() OVER (ORDER BY TotalScore DESC) AS TagRank
    FROM 
        TagStats
)
SELECT 
    rp.PostId,
    rp.Title,
    rp.CreationDate,
    rp.ViewCount,
    rp.Score,
    rp.OwnerDisplayName,
    tt.TAG AS TopTag,
    tt.PostCount,
    tt.TotalScore,
    tt.AverageScore
FROM 
    RankedPosts rp
JOIN 
    TopTags tt ON tt.Tag = ANY(string_to_array(TRIM(BOTH '<>' FROM rp.Tags), '>'))  -- Match the top tags with the post's tags
WHERE 
    rp.Rank = 1  -- Get only the top-ranked question for each user
ORDER BY 
    tt.TotalScore DESC, rp.ViewCount DESC;  -- Order by total score of top tags then view count

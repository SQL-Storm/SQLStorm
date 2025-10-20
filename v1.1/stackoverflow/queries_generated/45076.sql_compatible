WITH TopUserTags AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        tag AS Tag,
        COUNT(*) AS TagCount,
        AVG(p.Score) AS AvgPostScore,
        RANK() OVER (PARTITION BY tag ORDER BY COUNT(*) DESC) AS UserTagRank
    FROM 
        Users u
    JOIN 
        Posts p ON u.Id = p.OwnerUserId,
        LATERAL (
            SELECT TRIM(t) AS tag
            FROM (
                SELECT
                    REGEXP_SPLIT_TO_TABLE(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><') AS t
            ) s
        ) tags
    WHERE 
        p.PostTypeId = 1
        AND p.Score > 10
    GROUP BY 
        u.Id, u.DisplayName, tag
    HAVING 
        COUNT(*) > 5
)
SELECT 
    Tag,
    COUNT(DISTINCT UserId) AS UniqueUserCount,
    AVG(AvgPostScore) AS AverageTagScore,
    MAX(TagCount) AS MaxTagQuestions,
    SUM(CASE WHEN UserTagRank <= 3 THEN 1 ELSE 0 END) AS TopRankUsers
FROM 
    TopUserTags
WHERE 
    UserTagRank <= 10
GROUP BY 
    Tag
ORDER BY 
    UniqueUserCount DESC, 
    AverageTagScore DESC
LIMIT 50;
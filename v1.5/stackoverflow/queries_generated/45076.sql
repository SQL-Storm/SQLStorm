-- {"query": "45076.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 372}
WITH TopUserTags AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><')) AS Tag,
        COUNT(*) AS TagCount,
        AVG(p.Score) AS AvgPostScore,
        RANK() OVER (PARTITION BY UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><')) ORDER BY COUNT(*) DESC) AS UserTagRank
    FROM 
        Users u
    JOIN 
        Posts p ON u.Id = p.OwnerUserId
    WHERE 
        p.PostTypeId = 1
        AND p.Score > 10
    GROUP BY 
        u.Id, u.DisplayName, Tag
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

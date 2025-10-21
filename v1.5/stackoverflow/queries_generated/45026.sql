-- {"query": "45026.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 59644, "output_tokens": 10521} 
WITH UserTagActivity AS (
    SELECT 
        u.Id AS UserId, 
        t.TagName, 
        COUNT(DISTINCT p.Id) AS PostCount,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.ViewCount) AS MaxViewCount
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    CROSS JOIN LATERAL string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') tag(TagName)
    JOIN Tags t ON t.TagName = tag.TagName
    WHERE p.PostTypeId = 1
    GROUP BY u.Id, t.TagName
),
TagPerformanceRanking AS (
    SELECT 
        TagName,
        RANK() OVER (ORDER BY SUM(PostCount) DESC) AS PopularityRank,
        RANK() OVER (ORDER BY AVG(AvgPostScore) DESC) AS QualityRank
    FROM UserTagActivity
    GROUP BY TagName
)
SELECT 
    uta.TagName,
    tpr.PopularityRank,
    tpr.QualityRank,
    COUNT(DISTINCT uta.UserId) AS UniqueContributors,
    SUM(uta.PostCount) AS TotalPosts,
    ROUND(AVG(uta.AvgPostScore), 2) AS AverageTagScore,
    MAX(uta.MaxViewCount) AS MaxTagViewCount
FROM UserTagActivity uta
JOIN TagPerformanceRanking tpr ON uta.TagName = tpr.TagName
WHERE uta.PostCount > 5
GROUP BY uta.TagName, tpr.PopularityRank, tpr.QualityRank
ORDER BY UniqueContributors DESC, TotalPosts DESC
LIMIT 50;
-- {"query": "45061.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 314}
WITH UserTagPerformance AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName, 
        t.TagName,
        COUNT(p.Id) AS PostCount,
        AVG(p.Score) AS AvgPostScore,
        SUM(p.ViewCount) AS TotalViewCount,
        RANK() OVER (PARTITION BY t.TagName ORDER BY COUNT(p.Id) DESC) AS TagContributionRank
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    JOIN (SELECT Id, TagName FROM Tags) t ON t.TagName IN (
        SELECT UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><'))
    )
    WHERE p.PostTypeId = 1
    GROUP BY u.Id, u.DisplayName, t.TagName
)
SELECT 
    UserId, 
    DisplayName, 
    TagName,
    PostCount,
    AvgPostScore,
    TotalViewCount,
    TagContributionRank
FROM UserTagPerformance
WHERE TagContributionRank <= 10
ORDER BY PostCount DESC, AvgPostScore DESC
LIMIT 1000;

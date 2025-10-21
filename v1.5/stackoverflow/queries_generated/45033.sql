-- {"query": "45033.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 75702, "output_tokens": 13636} 
WITH PopularTagUsers AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        COUNT(DISTINCT t.Id) AS UniqueTagsContributed,
        AVG(p.Score) AS AveragePostScore,
        SUM(p.ViewCount) AS TotalViewCount
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    JOIN Tags t ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(DISTINCT t.Id) > 5
), 
RankedUsers AS (
    SELECT 
        *,
        DENSE_RANK() OVER (ORDER BY UniqueTagsContributed DESC, TotalViewCount DESC) AS ContributionRank
    FROM PopularTagUsers
)
SELECT 
    Id, 
    DisplayName, 
    UniqueTagsContributed, 
    AveragePostScore,
    TotalViewCount,
    ContributionRank
FROM RankedUsers
WHERE ContributionRank <= 100
ORDER BY ContributionRank, TotalViewCount DESC
LIMIT 50;
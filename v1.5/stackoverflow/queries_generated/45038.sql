-- {"query": "45038.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 256}
WITH TopTagContributors AS (
    SELECT 
        t.TagName,
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(p.Score) AS TotalScore,
        RANK() OVER (PARTITION BY t.TagName ORDER BY COUNT(DISTINCT p.Id) DESC) AS TagContributorRank
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 AND u.Reputation > 1000
    GROUP BY t.TagName, u.Id, u.DisplayName
)
SELECT 
    TagName,
    UserId,
    DisplayName,
    PostCount,
    TotalScore,
    TagContributorRank
FROM TopTagContributors
WHERE TagContributorRank <= 5
ORDER BY TagName, TagContributorRank
LIMIT 500;

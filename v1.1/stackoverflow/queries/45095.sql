-- {"query": "45095.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 217930, "output_tokens": 38856} 
WITH UserTagActivity AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName, 
        t.TagName, 
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(p.Score) AS TotalTagScore,
        AVG(p.ViewCount) AS AvgViewCount,
        MAX(p.CreationDate) AS LastTagActivity
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    JOIN LATERAL (
        SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag
    ) tags ON true
    JOIN Tags t ON t.TagName = tags.tag
    WHERE p.PostTypeId = 1
    GROUP BY u.Id, u.DisplayName, t.TagName
    HAVING COUNT(DISTINCT p.Id) > 10
),
TagInterconnections AS (
    SELECT 
        pl.PostId,
        pl.RelatedPostId,
        lt.Name AS LinkType,
        COUNT(*) AS InterconnectionCount
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    GROUP BY pl.PostId, pl.RelatedPostId, lt.Name
)
SELECT 
    uta.UserId,
    uta.DisplayName,
    uta.TagName,
    uta.PostCount,
    uta.TotalTagScore,
    uta.AvgViewCount,
    ti.LinkType,
    ti.InterconnectionCount
FROM UserTagActivity uta
JOIN TagInterconnections ti ON uta.PostCount > 20
ORDER BY uta.TotalTagScore DESC, ti.InterconnectionCount DESC
LIMIT 500;
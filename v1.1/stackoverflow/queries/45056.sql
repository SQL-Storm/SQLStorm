-- {"query": "45056.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 286}
WITH UserTagTopics AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName,
        t.TagName,
        COUNT(p.Id) AS PostCount,
        AVG(p.Score) AS AvgPostScore,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY COUNT(p.Id) DESC) AS TagRank
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    JOIN (
        SELECT Id, unnest(string_to_array(substring(Tags, 2, length(Tags)-2), '><')) AS TagName 
        FROM Posts 
        WHERE Tags IS NOT NULL
    ) t ON t.Id = p.Id
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, t.TagName
    HAVING COUNT(p.Id) > 10
)
SELECT 
    UserId,
    DisplayName,
    TagName,
    PostCount,
    AvgPostScore
FROM UserTagTopics
WHERE TagRank <= 3
ORDER BY PostCount DESC, AvgPostScore DESC
LIMIT 500;

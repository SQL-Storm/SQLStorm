-- {"query": "45097.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 461}
WITH UserTopTags AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        t.TagName,
        COUNT(p.Id) AS PostCount,
        RANK() OVER (PARTITION BY u.Id ORDER BY COUNT(p.Id) DESC) AS TagRank
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    JOIN (SELECT Id, unnest(string_to_array(substring(Tags, 2, length(Tags)-2), '><')) AS TagName FROM Posts) pt ON p.Id = pt.Id
    JOIN Tags t ON pt.TagName = t.TagName
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, t.TagName
), UserTopTagAnalytics AS (
    SELECT 
        UserId,
        DisplayName,
        SUM(CASE WHEN TagRank = 1 THEN PostCount ELSE 0 END) AS TopTagPostCount,
        COUNT(DISTINCT TagName) AS UniqueTopTags,
        AVG(PostCount) AS AverageTagPostCount
    FROM UserTopTags
    WHERE TagRank <= 3
    GROUP BY UserId, DisplayName
)
SELECT 
    utt.DisplayName,
    utt.TopTagPostCount,
    utt.UniqueTopTags,
    utt.AverageTagPostCount,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = utt.UserId) AS TotalBadges,
    (SELECT AVG(Score) FROM Posts p WHERE p.OwnerUserId = utt.UserId) AS AveragePostScore
FROM UserTopTagAnalytics utt
WHERE utt.UniqueTopTags > 2
ORDER BY utt.TopTagPostCount DESC, utt.UniqueTopTags DESC
LIMIT 500;

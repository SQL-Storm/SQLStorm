-- {"query": "45020.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 432}
WITH UserTopTags AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName,
        string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') AS UserTags,
        COUNT(p.Id) AS PostCount,
        AVG(p.Score) AS AvgPostScore
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1
    GROUP BY u.Id, u.DisplayName
),
TagRankings AS (
    SELECT 
        UserId, 
        DisplayName,
        PostCount,
        AvgPostScore,
        unnest(UserTags) AS Tag,
        DENSE_RANK() OVER (PARTITION BY UserId ORDER BY COUNT(*) DESC) AS TagRank
    FROM UserTopTags
    CROSS JOIN unnest(UserTags) AS UserTags
    GROUP BY UserId, DisplayName, PostCount, AvgPostScore, Tag
)
SELECT 
    tr.UserId,
    tr.DisplayName,
    tr.Tag,
    tr.PostCount,
    tr.AvgPostScore,
    tr.TagRank,
    COALESCE(t.Count, 0) AS GlobalTagCount,
    (SELECT COUNT(*) FROM Votes v JOIN Posts p ON v.PostId = p.Id WHERE p.Tags LIKE '%' || tr.Tag || '%' AND v.VoteTypeId = 2) AS TagUpvotes
FROM TagRankings tr
LEFT JOIN Tags t ON tr.Tag = t.TagName
WHERE tr.TagRank <= 3
ORDER BY tr.PostCount DESC, tr.AvgPostScore DESC
LIMIT 500;

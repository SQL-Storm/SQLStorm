WITH UserTopTags AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName,
        string_to_array(substring(p.Tags FROM 2 FOR length(p.Tags)-2), '><') AS UserTags,
        COUNT(p.Id) AS PostCount,
        AVG(p.Score) AS AvgPostScore
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1
    GROUP BY u.Id, u.DisplayName, string_to_array(substring(p.Tags FROM 2 FOR length(p.Tags)-2), '><')
),
TagRankings AS (
    SELECT 
        UserId, 
        DisplayName,
        PostCount,
        AvgPostScore,
        ut AS Tag,
        DENSE_RANK() OVER (PARTITION BY UserId ORDER BY COUNT(*) DESC) AS TagRank
    FROM UserTopTags
    CROSS JOIN unnest(UserTags) AS t(ut)
    GROUP BY UserId, DisplayName, PostCount, AvgPostScore, ut
)
SELECT 
    tr.UserId,
    tr.DisplayName,
    tr.Tag,
    tr.PostCount,
    tr.AvgPostScore,
    tr.TagRank,
    COALESCE(t.Count, 0) AS GlobalTagCount,
    (SELECT COUNT(*) FROM Votes v JOIN Posts p2 ON v.PostId = p2.Id WHERE p2.Tags LIKE '%' || tr.Tag || '%' AND v.VoteTypeId = 2) AS TagUpvotes
FROM TagRankings tr
LEFT JOIN Tags t ON tr.Tag = t.TagName
WHERE tr.TagRank <= 3
ORDER BY tr.PostCount DESC, tr.AvgPostScore DESC
LIMIT 500;
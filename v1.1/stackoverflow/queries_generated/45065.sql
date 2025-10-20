-- {"query": "45065.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 149110, "output_tokens": 26401} 
WITH UserTagStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        t.TagName,
        COUNT(p.Id) AS PostCount,
        AVG(p.Score) AS AvgPostScore,
        DENSE_RANK() OVER (PARTITION BY t.TagName ORDER BY COUNT(p.Id) DESC) AS UserTagRank
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    JOIN LATERAL string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') tag(TagName) ON true
    JOIN Tags t ON tag.TagName = t.TagName
    WHERE p.PostTypeId = 1
    GROUP BY u.Id, u.DisplayName, t.TagName
    HAVING COUNT(p.Id) > 10
),
RankedUserTags AS (
    SELECT 
        UserId,
        DisplayName,
        TagName,
        PostCount,
        AvgPostScore,
        UserTagRank
    FROM UserTagStats
    WHERE UserTagRank <= 5
)
SELECT 
    rut.UserId,
    rut.DisplayName,
    rut.TagName,
    rut.PostCount,
    rut.AvgPostScore,
    rut.UserTagRank,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = rut.UserId) AS TotalBadges,
    (SELECT SUM(v.BountyAmount) FROM Votes v WHERE v.UserId = rut.UserId AND v.VoteTypeId = 8) AS TotalBountiesStarted
FROM RankedUserTags rut
WHERE EXISTS (
    SELECT 1 
    FROM Badges b 
    WHERE b.UserId = rut.UserId AND b.Class = 1
)
ORDER BY rut.PostCount DESC, rut.AvgPostScore DESC
LIMIT 250;
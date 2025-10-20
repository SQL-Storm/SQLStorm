WITH TopUserTags AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName,
        -- use array_agg of DISTINCT tag names; ordering inside aggregation may not be supported in all dialects
        array_agg(DISTINCT t.TagName) AS TopTags,
        COUNT(DISTINCT p.Id) AS PostCount,
        AVG(p.Score) AS AverageScore
    FROM 
        Users u
    JOIN 
        Posts p ON u.Id = p.OwnerUserId
    JOIN 
        (SELECT Id, TagName FROM Tags) t ON t.TagName = ANY(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'))
    WHERE 
        p.PostTypeId = 1
        AND u.Reputation > 10000
    GROUP BY 
        u.Id, u.DisplayName
    HAVING 
        COUNT(DISTINCT p.Id) > 50
)
SELECT 
    tt.UserId,
    tt.DisplayName,
    tt.TopTags,
    tt.PostCount,
    tt.AverageScore,
    COALESCE(v.UpVotes, 0) AS UpVotes,
    COALESCE(b.GoldBadges, 0) AS GoldBadges
FROM 
    TopUserTags tt
LEFT JOIN (
    SELECT p.OwnerUserId AS UserId, COUNT(*) AS UpVotes
    FROM Votes v
    JOIN Posts p ON v.PostId = p.Id
    WHERE v.VoteTypeId = 2
    GROUP BY p.OwnerUserId
) v ON v.UserId = tt.UserId
LEFT JOIN (
    SELECT b.UserId, COUNT(*) AS GoldBadges
    FROM Badges b
    WHERE b.Class = 1
    GROUP BY b.UserId
) b ON b.UserId = tt.UserId
ORDER BY 
    tt.PostCount * tt.AverageScore DESC
LIMIT 100;
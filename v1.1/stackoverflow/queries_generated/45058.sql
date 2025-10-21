-- {"query": "45058.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 408}
WITH TopUserTags AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName,
        array_agg(DISTINCT t.TagName ORDER BY t.TagName) AS TopTags,
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
    (
        SELECT COUNT(*) 
        FROM Votes v 
        JOIN Posts p ON v.PostId = p.Id 
        WHERE p.OwnerUserId = tt.UserId AND v.VoteTypeId = 2
    ) AS UpVotes,
    (
        SELECT COUNT(*) 
        FROM Badges b 
        WHERE b.UserId = tt.UserId AND b.Class = 1
    ) AS GoldBadges
FROM 
    TopUserTags tt
ORDER BY 
    tt.PostCount * tt.AverageScore DESC
LIMIT 100;

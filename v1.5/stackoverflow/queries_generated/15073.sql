-- {"query": "15073.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 172790, "output_tokens": 50954} 
WITH UserTagStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        t.TagName,
        COUNT(p.Id) AS PostCount,
        AVG(p.Score) AS AvgTagScore,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY COUNT(p.Id) DESC) AS TagRank
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    JOIN LATERAL (
        SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
    ) tags ON true
    JOIN Tags t ON tags.TagName = t.TagName
    WHERE p.PostTypeId = 1
    GROUP BY u.Id, u.DisplayName, t.TagName
),
TopUserTags AS (
    SELECT 
        UserId, 
        DisplayName, 
        STRING_AGG(TagName, ', ' ORDER BY PostCount DESC) AS TopTags,
        MAX(PostCount) AS MaxTagPostCount
    FROM UserTagStats
    WHERE TagRank <= 3
    GROUP BY UserId, DisplayName
)
SELECT 
    tut.UserId,
    tut.DisplayName,
    tut.TopTags,
    tut.MaxTagPostCount,
    COALESCE(b.GoldBadges, 0) AS GoldBadges,
    COALESCE(b.SilverBadges, 0) AS SilverBadges,
    COALESCE(v.UpvoteCount, 0) AS TotalUpvotes,
    CASE 
        WHEN u.Reputation > 10000 THEN 'High Rep'
        WHEN u.Reputation > 1000 THEN 'Medium Rep'
        ELSE 'Low Rep'
    END AS ReputationTier,
    ROUND(
        100.0 * COALESCE(v.UpvoteCount, 0) / NULLIF(u.UpVotes + u.DownVotes, 0), 
        2
    ) AS UpvotePercentage
FROM TopUserTags tut
JOIN Users u ON tut.UserId = u.Id
LEFT JOIN (
    SELECT 
        UserId, 
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges
    FROM Badges
    GROUP BY UserId
) b ON tut.UserId = b.UserId
LEFT JOIN (
    SELECT 
        PostId, 
        COUNT(*) AS UpvoteCount
    FROM Votes 
    WHERE VoteTypeId = 2
    GROUP BY PostId
) v ON EXISTS (
    SELECT 1 
    FROM Posts p 
    WHERE p.OwnerUserId = tut.UserId 
    AND p.Id = v.PostId
)
WHERE u.Reputation > 100
ORDER BY tut.MaxTagPostCount DESC, v.UpvoteCount DESC
LIMIT 100;
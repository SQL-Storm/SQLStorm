-- {"query": "43038.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 526} 
WITH UserActivity AS (
    SELECT 
        OwnerUserId,
        COUNT(Id) AS PostsCreated,
        SUM(Score) AS TotalScore,
        AVG(Score) AS AvgScore,
        MAX(CreationDate) AS LastActivity
    FROM Posts
    WHERE OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
),
HighRepUsers AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        ua.PostsCreated,
        ua.TotalScore,
        ua.AvgScore,
        ua.LastActivity
    FROM Users u
    JOIN UserActivity ua ON u.Id = ua.OwnerUserId
    WHERE u.Reputation > 10000
),
TopTags AS (
    SELECT 
        t.TagName,
        COUNT(p.Id) AS TagCount
    FROM Posts p
    JOIN Tags t ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
    ORDER BY TagCount DESC
    LIMIT 10
),
BadgeCounts AS (
    SELECT 
        UserId,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
)
SELECT 
    hru.DisplayName,
    hru.Reputation,
    hru.PostsCreated,
    hru.TotalScore,
    hru.AvgScore,
    hru.LastActivity,
    bc.GoldBadges,
    bc.SilverBadges,
    bc.BronzeBadges
FROM HighRepUsers hru
LEFT JOIN BadgeCounts bc ON hru.Id = bc.UserId
WHERE EXISTS (
    SELECT 1
    FROM Posts p
    WHERE p.OwnerUserId = hru.Id
      AND p.CreationDate >= DATE_TRUNC('month', cast('2024-10-01' as date)) - INTERVAL '1 year'
)
ORDER BY hru.Reputation DESC
LIMIT 50;
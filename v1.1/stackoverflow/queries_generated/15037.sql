-- {"query": "15037.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 88730, "output_tokens": 26492} 
WITH UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(p.Id) AS PostCount,
        AVG(p.Score) AS AvgPostScore,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.ViewCount) AS MedianViewCount,
        RANK() OVER (ORDER BY COUNT(p.Id) DESC) AS PostCountRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY u.Id, u.DisplayName
),
TagPopularity AS (
    SELECT 
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS Tag,
        COUNT(*) AS TagCount,
        AVG(p.Score) AS AvgTagScore
    FROM Posts p
    WHERE p.Tags IS NOT NULL
    GROUP BY Tag
)
SELECT 
    ups.UserId,
    ups.DisplayName,
    ups.PostCount,
    ups.AvgPostScore,
    ups.MedianViewCount,
    tp.Tag AS MostFrequentTag,
    tp.TagCount,
    tp.AvgTagScore,
    CASE 
        WHEN ups.PostCount > 0 AND tp.TagCount > 100 THEN 'Influential'
        WHEN ups.PostCount > 10 THEN 'Active'
        ELSE 'Casual'
    END AS UserCategory,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = ups.UserId AND b.Class = 1) AS GoldBadgeCount,
    COALESCE(
        (SELECT MAX(v.CreationDate) 
         FROM Votes v 
         JOIN Posts p ON v.PostId = p.Id 
         WHERE p.OwnerUserId = ups.UserId AND v.VoteTypeId = 2), 
        '1970-01-01'::timestamp
    ) AS LastUpvoteReceived
FROM UserPostStats ups
JOIN TagPopularity tp ON tp.TagCount = (
    SELECT MAX(TagCount) 
    FROM TagPopularity tp2 
    WHERE tp2.Tag IN (
        SELECT unnest(string_to_array(substring(p2.Tags, 2, length(p2.Tags)-2), '><')) 
        FROM Posts p2 
        WHERE p2.OwnerUserId = ups.UserId
    )
)
WHERE ups.PostCount > 5 
  AND ups.AvgPostScore > 1
ORDER BY ups.PostCount * ups.AvgPostScore DESC
LIMIT 100;
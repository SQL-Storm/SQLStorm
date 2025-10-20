-- {"query": "15028.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 67715, "output_tokens": 20228} 
WITH UserActivityStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        AVG(p.Score) AS AvgPostScore,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS PostRank,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 100
    GROUP BY u.Id, u.DisplayName
),
TagPopularity AS (
    SELECT 
        UNNEST(STRING_TO_ARRAY(TRIM(p.Tags, '><'), '><')) AS Tag,
        COUNT(*) AS TagFrequency,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS MedianScore
    FROM Posts p
    WHERE p.PostTypeId = 1
    GROUP BY Tag
)
SELECT 
    uas.UserId,
    uas.DisplayName,
    uas.PostCount,
    uas.VoteCount,
    uas.AvgPostScore,
    uas.PostRank,
    uas.BadgeCount,
    tp.Tag AS MostFrequentTag,
    tp.TagFrequency,
    CASE 
        WHEN uas.PostCount > 100 THEN 'Highly Active'
        WHEN uas.PostCount > 50 THEN 'Moderately Active'
        ELSE 'Low Activity'
    END AS ActivityLevel,
    COALESCE(
        (SELECT SUM(v.BountyAmount) 
         FROM Votes v 
         WHERE v.UserId = uas.UserId AND v.VoteTypeId = 8),
        0
    ) AS TotalBountyStarted
FROM UserActivityStats uas
LEFT JOIN TagPopularity tp ON tp.TagFrequency = (
    SELECT MAX(TagFrequency) 
    FROM TagPopularity
)
WHERE uas.PostRank <= 1000
ORDER BY uas.PostCount DESC, uas.VoteCount DESC
LIMIT 100;
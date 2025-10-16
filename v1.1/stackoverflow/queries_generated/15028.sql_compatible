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
        tag AS Tag,
        COUNT(*) AS TagFrequency,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS MedianScore
    FROM Posts p,
    LATERAL (
      SELECT REGEXP_SPLIT_TO_TABLE(TRIM(BOTH '<>' FROM p.Tags), '><') AS tag
    ) AS t
    WHERE p.PostTypeId = 1
    GROUP BY tag
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
        (SELECT SUM(v2.BountyAmount) 
         FROM Votes v2 
         WHERE v2.UserId = uas.UserId AND v2.VoteTypeId = 8),
        0
    ) AS TotalBountyStarted
FROM UserActivityStats uas
LEFT JOIN TagPopularity tp ON tp.TagFrequency = (
    SELECT MAX(TagFrequency) 
    FROM TagPopularity
)
WHERE uas.PostRank <= 1000
GROUP BY
    uas.UserId,
    uas.DisplayName,
    uas.PostCount,
    uas.VoteCount,
    uas.AvgPostScore,
    uas.PostRank,
    uas.BadgeCount,
    tp.Tag,
    tp.TagFrequency
ORDER BY uas.PostCount DESC, uas.VoteCount DESC
LIMIT 100;
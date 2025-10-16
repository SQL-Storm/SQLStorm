-- {"query": "15081.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 191470, "output_tokens": 56279} 
WITH UserBadgeCounts AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) AS GoldBadgeCount,
        AVG(u.Reputation) OVER (PARTITION BY b.Class) AS ClassAvgReputation,
        FIRST_VALUE(b.Name) OVER (PARTITION BY u.Id ORDER BY b.Date DESC) AS LatestBadgeName
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId AND b.Class = 1
    WHERE u.Reputation > 1000
),
PostAnalytics AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Score,
        p.Tags,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
        COALESCE(NULLIF(p.ViewCount, 0), 1) AS NormalizedViews
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    GROUP BY p.Id
)
SELECT 
    ubc.UserId,
    ubc.DisplayName,
    ubc.GoldBadgeCount,
    ubc.ClassAvgReputation,
    pa.PostTypeId,
    pa.Score,
    pa.UpVotes,
    pa.DownVotes,
    ROUND(pa.UpVotes * 100.0 / pa.NormalizedViews, 2) AS EngagementRate,
    CASE 
        WHEN pa.Score > 10 THEN 'High Impact'
        WHEN pa.Score BETWEEN 0 AND 10 THEN 'Moderate Impact'
        ELSE 'Low Impact'
    END AS PostImpactCategory,
    ARRAY_LENGTH(STRING_TO_ARRAY(REPLACE(REPLACE(pa.Tags, '<', ''), '>', ''), ','), 1) AS TagCount
FROM UserBadgeCounts ubc
JOIN PostAnalytics pa ON ubc.UserId = (SELECT OwnerUserId FROM Posts WHERE Id = pa.Id)
WHERE ubc.GoldBadgeCount > 0
    AND pa.PostTypeId IN (1, 2)
ORDER BY EngagementRate DESC
LIMIT 100;
-- {"query": "28052.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1143} 

WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        RANK() OVER (ORDER BY SUM(p.Score) DESC) AS PostScoreRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2,3)
    WHERE u.CreationDate > '2010-01-01' AND (u.AboutMe LIKE '%SQL%' OR u.Location IS NULL)
    GROUP BY u.Id
    HAVING COUNT(p.Id) > 10
),
GoldBadgeUsers AS (
    SELECT 
        UserId,
        COUNT(*) AS GoldBadges,
        AVG(DATEDIFF('day', Date, CURRENT_DATE)) AS AvgDaysSinceBadge
    FROM Badges
    WHERE Class = 1 AND TagBased = 0
    GROUP BY UserId
)
SELECT 
    u.Id,
    u.DisplayName,
    COALESCE(ua.PostCount, 0) * 2 + COALESCE(gbu.GoldBadges, 0) * 10 AS ActivityScore,
    (SELECT AVG(Score) FROM Posts p2 WHERE p2.OwnerUserId = u.Id) AS AvgPostScore,
    STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, 5), '; ') AS TagSamples,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
    CASE 
        WHEN u.DownVotes > 100 THEN 'Controversial' 
        WHEN gbu.GoldBadges > 5 THEN 'Elite' 
        ELSE 'Regular' 
    END AS UserCategory
FROM Users u
LEFT JOIN UserActivity ua ON u.Id = ua.UserId
LEFT JOIN GoldBadgeUsers gbu ON u.Id = gbu.UserId
LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
WHERE u.Reputation > 1000
    AND EXISTS (
        SELECT 1 
        FROM PostHistory ph 
        WHERE ph.UserId = u.Id 
        AND ph.PostHistoryTypeId IN (10,11,12)
        AND ph.CreationDate BETWEEN '2020-01-01' AND '2023-01-01'
    )
    AND (LENGTH(u.AboutMe) - LENGTH(REPLACE(u.AboutMe, ' ', ''))) > 20
GROUP BY u.Id, u.DisplayName, u.Reputation, ua.PostCount, gbu.GoldBadges, u.DownVotes
UNION ALL
SELECT 
    -1 AS Id,
    'Community Wiki' AS DisplayName,
    COUNT(*) * 5 AS ActivityScore,
    NULL AS AvgPostScore,
    NULL AS TagSamples,
    0 AS ReputationRank,
    'System' AS UserCategory
FROM Posts 
WHERE OwnerUserId = -1 AND PostTypeId = 3
ORDER BY ReputationRank ASC, ActivityScore DESC
LIMIT 100 OFFSET 5;

-- {"query": "58031.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 1333} 

WITH ActiveUsers AS (
    SELECT 
        u.Id AS UserId, 
        u.Reputation, 
        COUNT(DISTINCT p.Id) AS PostCount, 
        COUNT(DISTINCT c.Id) AS CommentCount,
        AVG(p.Score) OVER (PARTITION BY u.Id) AS AvgPostScore
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1 AND p.CreationDate >= NOW() - INTERVAL '1 YEAR'
    LEFT JOIN Comments c ON c.UserId = u.Id AND c.CreationDate >= NOW() - INTERVAL '1 YEAR'
    GROUP BY u.Id, u.Reputation, p.Score
),
VoteStats AS (
    SELECT 
        v.UserId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS Upvotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS Downvotes,
        SUM(v.BountyAmount) AS TotalBounty
    FROM Votes v
    WHERE v.CreationDate >= NOW() - INTERVAL '1 YEAR'
    GROUP BY v.UserId
),
BadgeAchievers AS (
    SELECT 
        b.UserId,
        MAX(b.Date) AS LatestBadgeDate,
        STRING_AGG(b.Name, ', ' ORDER BY b.Date DESC) AS RecentBadges
    FROM Badges b
    WHERE b.Class = 1 AND b.Date >= NOW() - INTERVAL '6 MONTHS'
    GROUP BY b.UserId
    HAVING COUNT(b.Id) >= 3
)
SELECT 
    au.UserId,
    au.Reputation,
    au.PostCount,
    au.CommentCount,
    vs.Upvotes,
    vs.Downvotes,
    vs.TotalBounty,
    ba.LatestBadgeDate,
    ba.RecentBadges,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.UserId = au.UserId AND ph.PostHistoryTypeId = 5) AS EditsMade,
    RANK() OVER (ORDER BY au.Reputation DESC, vs.Upvotes DESC) AS UserRank
FROM ActiveUsers au
JOIN VoteStats vs ON vs.UserId = au.UserId
LEFT JOIN BadgeAchievers ba ON ba.UserId = au.UserId
WHERE au.Reputation > 10000
    AND au.PostCount > (SELECT AVG(PostCount) FROM ActiveUsers)
    AND EXISTS (
        SELECT 1 
        FROM Posts p 
        WHERE p.OwnerUserId = au.UserId 
        AND p.Tags LIKE '%<sql>%'
    )
ORDER BY 
    CASE 
        WHEN ba.LatestBadgeDate IS NOT NULL THEN 0 
        ELSE 1 
    END,
    UserRank
LIMIT 100;

-- {"query": "2038.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 381} 
WITH CTE_RecentPosts AS (
    SELECT p.Id, p.Title, p.CreationDate, p.OwnerUserId, RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1
),
CTE_TopBadges AS (
    SELECT b.UserId, COUNT(*) AS BadgeCount
    FROM Badges b
    WHERE b.Class = 1
    GROUP BY b.UserId
    HAVING COUNT(*) > 3
),
CTE_ActiveUsers AS (
    SELECT u.Id, u.DisplayName, COALESCE(u.Views, 0) + COALESCE(u.UpVotes, 0) - COALESCE(u.DownVotes, 0) AS InteractionScore
    FROM Users u
    WHERE u.LastAccessDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
)
SELECT u.Id AS UserId, u.DisplayName, COALESCE(p.Title, 'No Recent Post') AS RecentPostTitle, u.Reputation, tb.BadgeCount,  
       ac.InteractionScore, 
       CASE 
           WHEN u.Reputation > 1000 THEN 'High'
           WHEN u.Reputation > 500 THEN 'Medium'
           ELSE 'Low'
       END AS ReputationLevel
FROM Users u
LEFT JOIN CTE_RecentPosts p ON u.Id = p.OwnerUserId AND p.rn = 1
LEFT JOIN CTE_TopBadges tb ON u.Id = tb.UserId
LEFT JOIN CTE_ActiveUsers ac ON u.Id = ac.Id
WHERE tb.BadgeCount IS NOT NULL
ORDER BY u.Reputation DESC, ac.InteractionScore DESC, COALESCE(p.CreationDate, TIMESTAMP '1970-01-01') DESC;
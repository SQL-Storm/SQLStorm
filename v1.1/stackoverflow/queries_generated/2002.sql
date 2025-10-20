-- {"query": "2002.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 455} 

WITH UserActivityCTE AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        SUM(CASE WHEN p.CreationDate > current_date - interval '30 days' THEN 1 ELSE 0 END) AS RecentPosts,
        SUM(CASE WHEN c.CreationDate > current_date - interval '30 days' THEN 1 ELSE 0 END) AS RecentComments,
        SUM(CASE WHEN v.CreationDate > current_date - interval '30 days' 
                 AND v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS RecentUpVotes
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
TopUsersByActivity AS (
    SELECT UserId, DisplayName, RecentPosts + RecentComments + RecentUpVotes AS TotalActivity
    FROM UserActivityCTE
    WHERE RecentPosts + RecentComments + RecentUpVotes > 0
)
SELECT 
    tua.UserId,
    tua.DisplayName,
    tua.TotalActivity,
    CASE 
        WHEN SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) OVER (PARTITION BY tua.UserId) > 0 THEN 'Gold'
        WHEN SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY tua.UserId) > 0 THEN 'Silver'
        WHEN SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY tua.UserId) > 0 THEN 'Bronze'
        ELSE 'No Badge'
    END AS HighestBadge
FROM TopUsersByActivity tua
LEFT JOIN Badges b ON b.UserId = tua.UserId
WHERE NOT EXISTS (
    SELECT 1
    FROM Posts p
    WHERE p.OwnerUserId = tua.UserId 
    AND p.PostTypeId = 2 
    AND p.Score < 0
)
ORDER BY tua.TotalActivity DESC, tua.DisplayName
LIMIT 10;

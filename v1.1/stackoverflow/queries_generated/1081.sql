-- {"query": "1081.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 392} 

WITH RecentPosts AS (
    SELECT p.Id, p.Title, p.CreationDate, p.OwnerUserId, p.Score, p.ViewCount, 
           ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.CreationDate >= NOW() - INTERVAL '1 year'
),
UserReputation AS (
    SELECT u.Id AS UserId, u.Reputation, COUNT(DISTINCT p.Id) AS PostCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.Reputation
)
SELECT u.DisplayName, COALESCE(rp.Title, 'No posts in the last year') AS RecentPostTitle,
       u.Reputation, ur.PostCount, 
       COALESCE(v.UpVotes, 0) AS UpVotes, COALESCE(v.DownVotes, 0) AS DownVotes,
       CASE WHEN ur.Reputation IS NULL THEN 'New User' ELSE 'Established User' END AS UserStatus
FROM Users u
LEFT JOIN RecentPosts rp ON u.Id = rp.OwnerUserId AND rp.rn = 1
LEFT JOIN UserReputation ur ON u.Id = ur.UserId
LEFT JOIN (
    SELECT UserId, SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
           SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes
    GROUP BY UserId
) v ON u.Id = v.UserId
WHERE (u.Reputation > 100 OR u.CreationDate < NOW() - INTERVAL '6 months')
  AND (ur.PostCount IS NULL OR ur.PostCount > 0)
ORDER BY u.Reputation DESC, RecentPostTitle;

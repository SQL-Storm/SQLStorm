-- {"query": "1019.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 393} 
WITH RecentPosts AS (
    SELECT p.Id, p.Title, p.CreationDate, p.OwnerUserId, p.Score,
           ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as rn
    FROM Posts p
    WHERE p.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days'
),
UserReputation AS (
    SELECT u.Id AS UserId, u.Reputation,
           COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotes,
           COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotes
    FROM Users u
    LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY u.Id, u.Reputation
),
PostHistoryDetails AS (
    SELECT ph.PostId,
           ph.UserId,
           ph.Comment,
           ph.CreationDate,
           PHT.Name AS PostHistoryType
    FROM PostHistory ph
    JOIN PostHistoryTypes PHT ON ph.PostHistoryTypeId = PHT.Id
    WHERE ph.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '60 days'
)
SELECT rp.Title, rp.CreationDate, u.DisplayName AS Author,
       ur.Reputation, ur.UpVotes, ur.DownVotes, 
       COALESCE(pHD.Comment, 'No recent edits') AS RecentEditComment,
       pHD.CreationDate AS EditDate
FROM RecentPosts rp
JOIN Users u ON rp.OwnerUserId = u.Id
LEFT JOIN UserReputation ur ON u.Id = ur.UserId
LEFT JOIN PostHistoryDetails pHD ON rp.Id = pHD.PostId
WHERE rp.Score > 10
ORDER BY rp.CreationDate DESC
LIMIT 100;
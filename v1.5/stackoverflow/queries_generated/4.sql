-- {"query": "4.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 213} 
WITH userdata AS (
    SELECT u.Id, u.Reputation, COUNT(b.Id) AS BadgeCount
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.Reputation
),
postdata AS (
    SELECT p.Id, p.PostTypeId, p.Score, p.ViewCount, p.OwnerUserId, COALESCE(COUNT(c.Id), 0) AS CommentCount
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY p.Id, p.PostTypeId, p.Score, p.ViewCount, p.OwnerUserId
)
SELECT u.Id AS UserId, u.Reputation, u.BadgeCount, p.Id AS PostId, p.PostTypeId, p.Score, p.ViewCount, p.CommentCount
FROM userdata u
JOIN postdata p ON u.Id = p.OwnerUserId
WHERE u.Reputation > 1000
ORDER BY p.ViewCount DESC, p.Score DESC;
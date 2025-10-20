-- {"query": "1042.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 392} 

WITH RankedPosts AS (
    SELECT p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount,
           ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Score > 0
),
PostVotes AS (
    SELECT v.PostId, SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
           SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes
    FROM Votes v
    GROUP BY v.PostId
),
PostComments AS (
    SELECT c.PostId, COUNT(*) AS CommentCount
    FROM Comments c
    GROUP BY c.PostId
),
UserBadges AS (
    SELECT b.UserId, COUNT(*) AS BadgeCount
    FROM Badges b
    WHERE b.Date > NOW() - INTERVAL '1 year'
    GROUP BY b.UserId
)
SELECT rp.Title, rp.CreationDate, rp.Score, rp.ViewCount,
       COALESCE(pv.Upvotes, 0) AS Upvotes, COALESCE(pv.Downvotes, 0) AS Downvotes,
       COALESCE(pc.CommentCount, 0) AS CommentCount,
       COALESCE(ub.BadgeCount, 0) AS BadgeCount
FROM RankedPosts rp
LEFT JOIN PostVotes pv ON rp.Id = pv.PostId
LEFT JOIN PostComments pc ON rp.Id = pc.PostId
LEFT JOIN UserBadges ub ON rp.OwnerUserId = ub.UserId
WHERE rp.rn = 1
  AND (rp.ViewCount > 100 OR pv.Upvotes > 10)
ORDER BY rp.Score DESC, rp.CreationDate DESC
LIMIT 50;

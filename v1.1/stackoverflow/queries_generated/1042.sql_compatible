WITH RankedPosts AS (
    SELECT p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.OwnerUserId,
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
    WHERE b.Date > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
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
  AND (rp.ViewCount > 100 OR COALESCE(pv.Upvotes, 0) > 10)
GROUP BY rp.Title, rp.CreationDate, rp.Score, rp.ViewCount, rp.OwnerUserId, rp.rn,
         pv.Upvotes, pv.Downvotes, pc.CommentCount, ub.BadgeCount, rp.Id
ORDER BY rp.Score DESC, rp.CreationDate DESC
FETCH FIRST 50 ROWS ONLY;
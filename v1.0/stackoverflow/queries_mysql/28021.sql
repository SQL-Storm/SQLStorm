
WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Body,
        p.CreationDate,
        p.ViewCount,
        p.Score,
        u.DisplayName AS Owner,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.Tags ORDER BY p.CreationDate DESC) AS Rank
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 
)

SELECT
    rp.PostId,
    rp.Title,
    rp.Owner,
    rp.CreationDate,
    rp.ViewCount,
    rp.Score,
    rp.Tags,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = rp.PostId AND v.VoteTypeId = 2) AS UpVotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = rp.PostId AND v.VoteTypeId = 3) AS DownVotes,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.PostId) AS CommentCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = rp.PostId AND ph.PostHistoryTypeId IN (10, 11)) AS ClosureEvents,
    (SELECT GROUP_CONCAT(b.Name SEPARATOR ', ') 
     FROM Badges b 
     JOIN Users u ON b.UserId = u.Id 
     WHERE u.Id = (SELECT OwnerUserId FROM Posts WHERE Id = rp.PostId)) AS OwnerBadges
FROM RankedPosts rp
WHERE rp.Rank = 1
  AND rp.ViewCount > 100
GROUP BY rp.PostId, rp.Title, rp.Owner, rp.CreationDate, rp.ViewCount, rp.Score, rp.Tags
ORDER BY rp.Score DESC, rp.CreationDate DESC
LIMIT 10;

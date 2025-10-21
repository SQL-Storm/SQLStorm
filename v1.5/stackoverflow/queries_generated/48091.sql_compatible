WITH RankedPosts AS (
    SELECT
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        u.DisplayName AS OwnerDisplayName,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC, p.Id ASC) AS rn
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= cast('2024-10-01' as date) - INTERVAL '30 days'
),
AggregatedPostData AS (
    SELECT
        rp.Id,
        rp.Title,
        rp.CreationDate,
        rp.Score,
        rp.ViewCount,
        rp.OwnerDisplayName,
        rp.CommentCount,
        (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = rp.Id AND ph.PostHistoryTypeId IN (4, 5, 6)) AS EditCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = rp.Id AND v.VoteTypeId = 2) AS UpvoteCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = rp.Id AND v.VoteTypeId = 3) AS DownvoteCount,
        CASE WHEN rp.rn <= 100 THEN TRUE ELSE FALSE END AS IsTop100Ranked
    FROM RankedPosts rp
)
SELECT
    apd.Id,
    apd.Title,
    apd.CreationDate,
    apd.Score,
    apd.ViewCount,
    apd.OwnerDisplayName,
    apd.CommentCount,
    apd.EditCount,
    apd.UpvoteCount,
    apd.DownvoteCount,
    apd.IsTop100Ranked,
    (SELECT COUNT(*) FROM Comments c JOIN Users u ON c.UserId = u.Id WHERE c.PostId = apd.Id AND u.Reputation > 10000) AS HighReputationCommenterCount,
    (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = apd.Id AND v.VoteTypeId = 8 AND v.BountyAmount IS NOT NULL) AS AverageBountyAmount
FROM AggregatedPostData apd
WHERE apd.ViewCount > 500
ORDER BY apd.Score DESC, apd.ViewCount DESC
LIMIT 50;
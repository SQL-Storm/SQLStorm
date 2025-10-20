SELECT 
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    u.DisplayName AS OwnerName,
    u.Reputation,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.Tags,
    (SELECT COUNT(*) FROM Posts WHERE ParentId = p.Id AND PostTypeId = 2) AS AnswerCountCorrected,
    (SELECT COUNT(*) FROM Comments WHERE PostId = p.Id) AS CommentCountCorrected,
    (SELECT STRING_AGG(DISTINCT CAST(v.VoteTypeId AS VARCHAR), ',') FROM Votes v WHERE v.PostId = p.Id) AS VoteTypes,
    (SELECT COUNT(DISTINCT UserId) FROM Votes WHERE PostId = p.Id AND VoteTypeId IN (2,3)) AS VoteUsers,
    (SELECT STRING_AGG(CAST(HistoryId AS VARCHAR), ',') FROM (
        SELECT ph.Id AS HistoryId, ph.CreationDate
        FROM PostHistory ph
        WHERE ph.PostId = p.Id
          AND ph.PostHistoryTypeId IN (1,2,3,4,5,6)
        ORDER BY ph.CreationDate DESC
        LIMIT 5
    ) sub) AS RecentHistoryEvents,
    (SELECT MAX(BountyAmount) FROM Votes WHERE PostId = p.Id AND VoteTypeId = 8) AS MaxBounty,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Class = 1) AS GoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Class = 2) AS SilverBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Class = 3) AS BronzeBadges,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) AS DuplicateLinks,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 1) AS LinkedPosts
FROM Posts p
INNER JOIN Users u ON p.OwnerUserId = u.Id
WHERE p.PostTypeId = 1 
  AND p.Score > 100
  AND p.ViewCount > 1000
  AND p.CreationDate >= DATE '2020-01-01'
  AND p.Tags IS NOT NULL
  AND p.Tags <> ''
  AND u.Reputation > 5000
  AND u.AccountId IS NOT NULL
  AND EXISTS (
    SELECT 1 FROM Votes v 
    WHERE v.PostId = p.Id 
      AND v.VoteTypeId IN (2,3) 
      AND v.CreationDate >= DATE '2020-01-01'
)
GROUP BY
    p.Id,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    u.DisplayName,
    u.Reputation,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.Tags,
    p.OwnerUserId
ORDER BY p.Score DESC, p.ViewCount DESC
LIMIT 1000;
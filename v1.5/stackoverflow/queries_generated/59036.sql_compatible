SELECT 
    p.Id as PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    u.DisplayName as OwnerName,
    u.Reputation,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.Tags,
    (SELECT COUNT(*) FROM Posts WHERE ParentId = p.Id AND PostTypeId = 2) as AnswerCountCorrected,
    (SELECT COUNT(*) FROM Comments WHERE PostId = p.Id) as CommentCountCorrected,
    (SELECT STRING_AGG(DISTINCT CAST(v.VoteTypeId AS TEXT), ',') FROM Votes v WHERE v.PostId = p.Id) as VoteTypes,
    (SELECT COUNT(DISTINCT UserId) FROM Votes WHERE PostId = p.Id AND VoteTypeId IN (2,3)) as VoteUsers,
    (SELECT STRING_AGG(CAST(HistoryId AS VARCHAR), ',') FROM (
        SELECT ph.Id as HistoryId, ph.CreationDate
        FROM PostHistory ph
        WHERE ph.PostId = p.Id
        AND ph.PostHistoryTypeId IN (1,2,3,4,5,6)
        ORDER BY ph.CreationDate DESC
        LIMIT 5
    ) sub) as RecentHistoryEvents,
    (SELECT MAX(BountyAmount) FROM Votes WHERE PostId = p.Id AND VoteTypeId = 8) as MaxBounty,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Class = 1) as GoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Class = 2) as SilverBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Class = 3) as BronzeBadges,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) as DuplicateLinks,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 1) as LinkedPosts
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
ORDER BY p.Score DESC, p.ViewCount DESC
LIMIT 1000;
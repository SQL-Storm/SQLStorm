SELECT 
    p.Id as PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.CreationDate,
    u.DisplayName as OwnerDisplayName,
    u.Reputation as OwnerReputation,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) as UpvoteCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) as DownvoteCount,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) as CommentCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (10, 11, 12, 13)) as EditCount,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Class = 1) as GoldBadgeCount,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Class = 2) as SilverBadgeCount,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Class = 3) as BronzeBadgeCount,
    (
        SELECT STRING_AGG(t.TagName, ', ') 
        FROM (
            SELECT CAST(value AS VARCHAR) AS TagName
            FROM (
                SELECT UNNEST(string_to_array(trim(both '<' FROM trim(p.Tags)) , '>')) AS value
            ) AS inner_t
            WHERE value IS NOT NULL AND value <> ''
        ) AS t
    ) as TagsList,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.ParentId = p.Id AND p2.PostTypeId = 2) as AnswerCountActual,
    (SELECT MAX(ph.CreationDate) FROM PostHistory ph WHERE ph.PostId = p.Id) as LastPostHistoryDate,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) as DuplicateLinkCount,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.RelatedPostId = p.Id AND pl.LinkTypeId = 3) as DuplicateOfCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 5) as FavoriteCountCurrent,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 8) as BountyStartCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 9) as BountyCloseCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (19, 20)) as ProtectionCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (14, 15)) as LockUnlockCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (16, 17, 35, 36)) as CommunityOwnerMigrationCount
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
WHERE p.PostTypeId = 1 
    AND p.CreationDate >= DATE '2022-01-01'
    AND p.Score >= 0
    AND p.ViewCount >= 100
    AND p.AnswerCount >= 0
    AND (p.Tags IS NOT NULL AND p.Tags != '')
    AND u.Reputation >= 1000
    AND u.CreationDate >= DATE '2020-01-01'
    AND (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (1, 2, 3)) > 0
ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC
LIMIT 10000;
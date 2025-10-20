SELECT 
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.Tags,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCountActual,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVotes,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Class = 1) AS GoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Class = 2) AS SilverBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Class = 3) AS BronzeBadges,
    (SELECT STRING_AGG(t.TagName, ', ') FROM (
        SELECT TRIM(BOTH '<' FROM TRIM(BOTH '>' FROM s)) AS TagName
        FROM (
            SELECT UNNEST(STRING_TO_ARRAY(p.Tags, '><')) AS s
        ) sub
    ) t WHERE t.TagName IS NOT NULL AND t.TagName <> '') AS TagList,
    (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = p.Id AND a.PostTypeId = 2) AS AnswerCountActual,
    (SELECT MAX(ph.CreationDate) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (10, 11, 12, 13)) AS LastModerationAction,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) AS DuplicateLinks,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.RelatedPostId = p.Id AND pl.LinkTypeId = 1) AS LinkedFromCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 1) AS InitialTitleChanges,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 2) AS InitialBodyChanges,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 3) AS InitialTagChanges,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 6) AS TagEdits,
    (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 8) AS AvgBountyAmount
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
WHERE p.PostTypeId = 1 
    AND p.CreationDate >= DATE '2022-01-01'
    AND p.Score >= 10
    AND p.ViewCount >= 1000
    AND p.AnswerCount >= 2
    AND EXISTS (SELECT 1 FROM Comments c WHERE c.PostId = p.Id AND c.CreationDate >= DATE '2022-01-01')
    AND EXISTS (SELECT 1 FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId IN (2, 3))
    AND EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Class IN (1, 2, 3))
ORDER BY p.Score DESC, p.ViewCount DESC
LIMIT 1000;
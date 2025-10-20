SELECT 
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    COUNT(DISTINCT c.Id) AS CommentCount,
    COUNT(DISTINCT v.Id) AS VoteCount,
    COUNT(DISTINCT bh.Id) AS HistoryCount,
    STRING_AGG(DISTINCT t.TagName, ', ') AS Tags,
    CASE 
        WHEN p.PostTypeId = 1 THEN 'Question'
        WHEN p.PostTypeId = 2 THEN 'Answer'
        WHEN p.PostTypeId = 3 THEN 'Wiki'
        WHEN p.PostTypeId = 4 THEN 'TagWikiExcerpt'
        WHEN p.PostTypeId = 5 THEN 'TagWiki'
        WHEN p.PostTypeId = 6 THEN 'ModeratorNomination'
        WHEN p.PostTypeId = 7 THEN 'WikiPlaceholder'
        WHEN p.PostTypeId = 8 THEN 'PrivilegeWiki'
    END AS PostType,
    MAX(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS HasUpvotes,
    MAX(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS HasDownvotes,
    MAX(CASE WHEN vt.Name = 'Favorite' THEN 1 ELSE 0 END) AS HasFavorites,
    MAX(CASE WHEN vt.Name = 'Close' THEN 1 ELSE 0 END) AS HasCloseVotes,
    MAX(CASE WHEN vt.Name = 'Reopen' THEN 1 ELSE 0 END) AS HasReopenVotes,
    COUNT(DISTINCT CASE WHEN bh.PostHistoryTypeId IN (10, 11) THEN bh.Id END) AS ClosedReopenedCount,
    COUNT(DISTINCT CASE WHEN bh.PostHistoryTypeId IN (12, 13) THEN bh.Id END) AS DeletedUndeletedCount,
    COUNT(DISTINCT CASE WHEN bh.PostHistoryTypeId IN (14, 15) THEN bh.Id END) AS LockedUnlockedCount,
    COUNT(DISTINCT CASE WHEN bh.PostHistoryTypeId IN (16, 17, 18, 19, 20, 22, 24, 25, 31, 33, 34, 35, 36, 37, 38, 50, 52, 53, 66) THEN bh.Id END) AS SpecialHistoryEvents,
    COUNT(DISTINCT pl.Id) AS LinkCount,
    COUNT(DISTINCT b.Id) AS BadgeCount,
    AVG(EXTRACT(EPOCH FROM (CASE WHEN v.VoteTypeId IN (2, 3) THEN v.CreationDate END))) AS AvgVoteEpoch,
    TO_TIMESTAMP(AVG(EXTRACT(EPOCH FROM (CASE WHEN v.VoteTypeId IN (2, 3) THEN v.CreationDate END)))) AS AvgVoteDate,
    MAX(CASE WHEN bh.PostHistoryTypeId = 1 THEN bh.CreationDate END) AS InitialTitleDate,
    MAX(CASE WHEN bh.PostHistoryTypeId = 2 THEN bh.CreationDate END) AS InitialBodyDate,
    MAX(CASE WHEN bh.PostHistoryTypeId = 3 THEN bh.CreationDate END) AS InitialTagsDate
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
LEFT JOIN PostHistory bh ON p.Id = bh.PostId
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
LEFT JOIN Tags t ON p.Tags LIKE '%' || t.TagName || '%'
LEFT JOIN Badges b ON p.OwnerUserId = b.UserId
WHERE p.CreationDate > TIMESTAMP '2020-01-01'
    AND p.Score > 0
    AND p.PostTypeId IN (1, 2)
GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, u.DisplayName, u.Reputation, p.PostTypeId
HAVING COUNT(DISTINCT c.Id) > 5
    AND COUNT(DISTINCT v.Id) > 10
    AND COUNT(DISTINCT bh.Id) > 20
    AND COUNT(DISTINCT pl.Id) > 0
ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC
LIMIT 50000;
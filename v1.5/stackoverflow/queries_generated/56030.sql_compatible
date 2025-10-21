SELECT 
    p.Id, 
    p.Title, 
    p.Score, 
    p.ViewCount, 
    p.CreationDate, 
    ph.PostHistoryTypeId, 
    ph.CreationDate AS PostHistoryCreationDate, 
    u.Reputation, 
    u.DisplayName, 
    v.VoteTypeId, 
    v.CreationDate AS VoteCreationDate, 
    t.TagName, 
    pl.LinkTypeId, 
    pl.CreationDate AS PostLinkCreationDate
FROM 
    Posts p
JOIN 
    PostHistory ph ON p.Id = ph.PostId
JOIN 
    Users u ON p.OwnerUserId = u.Id
JOIN 
    Votes v ON p.Id = v.PostId
JOIN 
    PostLinks pl ON p.Id = pl.PostId
JOIN 
    Tags t ON p.Id = t.ExcerptPostId
WHERE 
    p.PostTypeId = 1 
    AND ph.PostHistoryTypeId = 10 
    AND v.VoteTypeId = 2 
    AND pl.LinkTypeId = 1 
    AND CAST(t.IsModeratorOnly AS INTEGER) = 0 
    AND CAST(u.Reputation AS INTEGER) > 1000 
    AND p.CreationDate > TIMESTAMP '2020-01-01 00:00:00' 
    AND ph.CreationDate > TIMESTAMP '2020-01-01 00:00:00' 
    AND v.CreationDate > TIMESTAMP '2020-01-01 00:00:00' 
    AND pl.CreationDate > TIMESTAMP '2020-01-01 00:00:00'
ORDER BY 
    p.Score DESC, 
    p.ViewCount DESC, 
    u.Reputation DESC;
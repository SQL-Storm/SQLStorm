-- {"query": "44030.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 68820, "output_tokens": 26262} 
Here is an elaborate SQL query for performance benchmarking:

SELECT 
    p.Id AS PostId, 
    p.PostTypeId, 
    p.OwnerUserId, 
    p.CreationDate, 
    p.Score, 
    p.ViewCount, 
    p.AnswerCount, 
    p.CommentCount, 
    p.FavoriteCount, 
    p.ClosedDate, 
    p.CommunityOwnedDate, 
    u.Id AS UserId, 
    u.Reputation, 
    u.CreationDate AS UserCreationDate, 
    u.LastAccessDate, 
    b.Id AS BadgeId, 
    b.Name AS BadgeName, 
    b.Date AS BadgeDate, 
    b.Class AS BadgeClass, 
    b.TagBased AS BadgeTagBased, 
    c.Id AS CommentId, 
    c.Score AS CommentScore, 
    c.CreationDate AS CommentCreationDate, 
    v.Id AS VoteId, 
    v.VoteTypeId, 
    v.CreationDate AS VoteCreationDate, 
    v.BountyAmount, 
    pl.Id AS PostLinkId, 
    pl.LinkTypeId, 
    pl.CreationDate AS PostLinkCreationDate, 
    pt.Name AS PostTypeName, 
    lt.Name AS LinkTypeName, 
    vt.Name AS VoteTypeName, 
    crt.Name AS CloseReasonTypeName, 
    pht.Name AS PostHistoryTypeName
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Badges b ON b.UserId = u.Id
LEFT JOIN Comments c ON c.PostId = p.Id
LEFT JOIN Votes v ON v.PostId = p.Id
LEFT JOIN PostLinks pl ON pl.PostId = p.Id
LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
LEFT JOIN CloseReasonTypes crt ON p.ClosedDate IS NOT NULL AND CAST(p.Body AS VARCHAR(50)) LIKE '%[' + CAST(crt.Id AS VARCHAR(10)) + ']%'
LEFT JOIN PostHistory ph ON ph.PostId = p.Id
LEFT JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
WHERE p.Id IN (
    SELECT Id FROM Posts
    WHERE CreationDate BETWEEN '2010-01-01' AND '2022-12-31'
    ORDER BY ViewCount DESC
    LIMIT 1000
)
ORDER BY p.ViewCount DESC
LIMIT 100;
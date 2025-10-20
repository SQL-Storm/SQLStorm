SELECT 
    p.Id AS PostId,
    p.Title AS PostTitle,
    p.CreationDate AS PostCreationDate,
    p.Score AS PostScore,
    p.ViewCount AS PostViewCount,
    p.Body AS PostBody,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    COUNT(DISTINCT v.Id) AS TotalVotes,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    COUNT(DISTINCT t.Id) AS TagCount,
    COUNT(DISTINCT a.Id) AS AnswerCount,
    COUNT(DISTINCT c.Id) AS CommentCount,
    AVG(CASE WHEN v.VoteTypeId = 2 THEN v.BountyAmount ELSE NULL END) AS AvgBountyUpVotes,
    AVG(CASE WHEN v.VoteTypeId = 3 THEN v.BountyAmount ELSE NULL END) AS AvgBountyDownVotes,
    MAX(ph.CreationDate) AS LastEditDate,
    MAX(c.CreationDate) AS LastCommentDate,
    MAX(GREATEST(
        COALESCE(v.CreationDate, TIMESTAMP '0001-01-01'),
        COALESCE(c.CreationDate, TIMESTAMP '0001-01-01'),
        COALESCE(ph.CreationDate, TIMESTAMP '0001-01-01')
    )) AS LastActivityDate
FROM 
    Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN Posts a ON p.Id = a.ParentId
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN Tags t ON p.Id = t.ExcerptPostId
GROUP BY 
    p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.Body, u.DisplayName, u.Reputation
ORDER BY 
    p.Score DESC, p.ViewCount DESC, p.CreationDate DESC
LIMIT 100;
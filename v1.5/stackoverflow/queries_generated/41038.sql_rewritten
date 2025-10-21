-- {"query": "41038.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 507} 
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
    SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedVotes,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    COUNT(DISTINCT c.Id) AS TotalComments,
    COUNT(DISTINCT pa.Id) AS TotalAnswers,
    COUNT(DISTINCT pl.Id) AS TotalLinks,
    AVG(CASE WHEN v.VoteTypeId = 1 THEN v.BountyAmount ELSE 0 END) AS AvgBountyAmount,
    MAX(c.CreationDate) AS LatestCommentDate,
    MAX(pa.CreationDate) AS LatestAnswerDate,
    MAX(pl.CreationDate) AS LatestLinkDate,
    STRING_AGG(DISTINCT t.TagName, ', ') AS Tags
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Comments c ON p.Id = c.PostId
LEFT JOIN 
    Posts pa ON p.Id = pa.ParentId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    Tags t ON p.Id = t.Id
GROUP BY 
    p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.Body, u.DisplayName, u.Reputation
ORDER BY 
    p.CreationDate DESC, p.Score DESC, p.ViewCount DESC, TotalVotes DESC, TotalComments DESC, TotalAnswers DESC, TotalLinks DESC, AvgBountyAmount DESC, LatestCommentDate DESC, LatestAnswerDate DESC, LatestLinkDate DESC;
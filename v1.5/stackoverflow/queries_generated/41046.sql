-- {"query": "41046.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 446} 

SELECT 
    p.Id AS PostId,
    p.Title AS PostTitle,
    p.CreationDate AS PostCreationDate,
    p.Score AS PostScore,
    p.ViewCount AS PostViewCount,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    COUNT(DISTINCT v.Id) AS TotalVotes,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
    AVG(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS AvgUpVotes,
    AVG(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS AvgDownVotes,
    COUNT(DISTINCT c.Id) AS CommentCount,
    COUNT(DISTINCT a.Id) AS AnswerCount,
    COUNT(DISTINCT ph.Id) AS PostHistoryCount,
    COUNT(DISTINCT pl.Id) AS PostLinkCount,
    COUNT(DISTINCT t.Id) AS TagCount
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Comments c ON p.Id = c.PostId
LEFT JOIN 
    Posts a ON p.Id = a.ParentId AND a.PostTypeId = 2
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    Tags t ON p.Id = t.Id
GROUP BY 
    p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, u.DisplayName, u.Reputation
ORDER BY 
    p.CreationDate DESC, p.Score DESC, p.ViewCount DESC
LIMIT 100;

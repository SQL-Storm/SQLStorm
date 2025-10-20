-- {"query": "41099.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 621} 

SELECT 
    p.Id AS PostId,
    p.Title AS PostTitle,
    p.CreationDate AS PostCreationDate,
    p.Score AS PostScore,
    p.ViewCount AS PostViewCount,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    COUNT(DISTINCT v.Id) AS TotalVotes,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.UserId ELSE NULL END) AS UniqueUpVoters,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.UserId ELSE NULL END) AS UniqueDownVoters,
    AVG(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS AvgUpVotesPerPost,
    AVG(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS AvgDownVotesPerPost,
    COUNT(DISTINCT c.Id) AS TotalComments,
    COUNT(DISTINCT a.Id) AS TotalAnswers,
    COUNT(DISTINCT pt.Id) AS TotalPostTypes,
    COUNT(DISTINCT vh.PostHistoryTypeId) AS TotalPostHistoryTypes,
    COUNT(DISTINCT pl.Id) AS TotalPostLinks,
    COUNT(DISTINCT t.Id) AS TotalTags,
    COUNT(DISTINCT b.Id) AS TotalBadges
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Comments c ON p.Id = c.PostId
LEFT JOIN 
    Posts a ON p.Id = a.ParentId
LEFT JOIN 
    PostHistory vh ON p.Id = vh.PostId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
LEFT JOIN 
    Tags t ON p.Id = t.Id
LEFT JOIN 
    Badges b ON u.Id = b.UserId
GROUP BY 
    p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, u.DisplayName, u.Reputation
HAVING 
    p.PostTypeId = 1 AND p.CreationDate > '2022-01-01' AND u.Reputation > 100
ORDER BY 
    p.Score DESC, p.ViewCount DESC, TotalVotes DESC, TotalComments DESC, TotalAnswers DESC, TotalPostHistoryTypes DESC, TotalPostLinks DESC, TotalTags DESC, TotalBadges DESC
LIMIT 100;

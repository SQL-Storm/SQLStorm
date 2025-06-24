-- Performance Benchmarking Query
-- This query retrieves statistics about posts, including their scores, view counts, and user reputations,
-- and filters for posts of type "Question" with a specific time frame.

SELECT 
    p.Id AS PostId,
    p.Title,
    p.CreationDate AS PostCreationDate,
    p.Score,
    p.ViewCount,
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(c.Id) AS CommentCount,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Comments c ON p.Id = c.PostId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
WHERE 
    p.PostTypeId = 1 -- PostTypeId = 1 for Questions
    AND p.CreationDate >= '2022-01-01' -- Start Date
    AND p.CreationDate < '2023-01-01' -- End Date
GROUP BY 
    p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, u.Id, u.DisplayName, u.Reputation
ORDER BY 
    p.CreationDate DESC;    

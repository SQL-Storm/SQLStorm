-- Performance Benchmarking SQL Query

-- This query retrieves user reputation information and their posts along with the count of comments and votes on those posts.
-- It is designed to analyze performance and assess the relationships between users, their reputation, and post interactions.

SELECT 
    u.Id AS UserId,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    p.Id AS PostId,
    p.Title,
    p.CreationDate AS PostCreationDate,
    COUNT(c.Id) AS CommentCount,
    COUNT(v.Id) AS VoteCount
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Comments c ON p.Id = c.PostId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
GROUP BY 
    u.Id, u.Reputation, u.CreationDate, p.Id, p.Title, p.CreationDate
ORDER BY 
    u.Reputation DESC, CommentCount DESC, VoteCount DESC;

-- {"query": "58072.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 1732} 

SELECT 
    u.Id AS UserId,
    u.DisplayName,
    p.Id AS PostId,
    p.Title,
    COUNT(DISTINCT c.Id) AS CommentCount,
    COUNT(DISTINCT v.Id) AS VoteCount,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
    COUNT(DISTINCT b.Id) AS BadgeCount,
    COUNT(DISTINCT ph.Id) AS EditCount,
    AVG(p.Score) OVER (PARTITION BY u.Id) AS AvgPostScore,
    RANK() OVER (ORDER BY u.Reputation DESC) AS UserRank
FROM 
    Users u
INNER JOIN 
    Posts p ON u.Id = p.OwnerUserId
INNER JOIN 
    Comments c ON p.Id = c.PostId
INNER JOIN 
    Votes v ON p.Id = v.PostId
INNER JOIN 
    Badges b ON u.Id = b.UserId
INNER JOIN 
    PostHistory ph ON p.Id = ph.PostId
WHERE 
    p.PostTypeId = 1
    AND p.CreationDate BETWEEN '2010-01-01' AND '2020-12-31'
    AND b.Class = 1
    AND ph.PostHistoryTypeId = 5
GROUP BY 
    u.Id, u.DisplayName, p.Id, p.Title, u.Reputation, p.Score
HAVING 
    COUNT(DISTINCT c.Id) > (SELECT AVG(CommentCount) FROM (SELECT PostId, COUNT(Id) AS CommentCount FROM Comments GROUP BY PostId) AS sub)
ORDER BY 
    UserRank ASC,
    Upvotes DESC,
    EditCount DESC
LIMIT 100;

-- {"query": "32063.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 298} 
SELECT 
    u.Id AS UserId, 
    u.DisplayName, 
    u.Reputation, 
    COUNT(DISTINCT p.Id) AS PostCount, 
    COUNT(DISTINCT c.Id) AS CommentCount,
    COUNT(DISTINCT v.Id) AS VoteCount,
    COUNT(DISTINCT b.Id) AS BadgeCount,
    SUM(CASE WHEN ph.PostHistoryTypeId IN (5, 8) THEN 1 ELSE 0 END) AS EditHistoryCount,
    SUM(CASE WHEN pl.LinkTypeId = 1 THEN 1 ELSE 0 END) AS LinkedPostCount,
    RANK() OVER (ORDER BY u.Reputation DESC) AS UserReputationRank
FROM 
    Users u
JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Comments c ON u.Id = c.UserId
LEFT JOIN 
    Votes v ON u.Id = v.UserId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    PostHistory ph ON u.Id = ph.UserId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
WHERE 
    u.CreationDate >= '2020-01-01' 
    AND u.Reputation > 1000
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
ORDER BY 
    UserReputationRank, PostCount DESC;
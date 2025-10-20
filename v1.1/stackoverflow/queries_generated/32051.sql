-- {"query": "32051.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 254} 

SELECT 
    u.Id AS UserId, 
    u.DisplayName, 
    p.Id AS PostId, 
    p.Title, 
    p.Score, 
    p.ViewCount, 
    c.CommentCount, 
    v.VoteCount, 
    b.BadgeCount
FROM 
    Users u
JOIN 
    (SELECT OwnerUserId, COUNT(Id) AS PostCount, SUM(Score) AS TotalScore FROM Posts WHERE PostTypeId = 1 GROUP BY OwnerUserId) p ON u.Id = p.OwnerUserId
LEFT JOIN 
    (SELECT PostId, COUNT(Id) AS CommentCount FROM Comments GROUP BY PostId) c ON p.OwnerUserId = c.PostId
LEFT JOIN 
    (SELECT PostId, COUNT(Id) AS VoteCount FROM Votes WHERE VoteTypeId IN (2, 3) GROUP BY PostId) v ON p.OwnerUserId = v.PostId
LEFT JOIN 
    (SELECT UserId, COUNT(Id) AS BadgeCount FROM Badges GROUP BY UserId) b ON u.Id = b.UserId
WHERE 
    p.TotalScore > 100
ORDER BY 
    p.TotalScore DESC, p.PostCount DESC
LIMIT 10;


SELECT p.Id AS PostId, 
       p.Title, 
       p.CreationDate, 
       u.DisplayName AS Author,
       p.Score, 
       (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
WHERE p.PostTypeId = 1  
GROUP BY p.Id, p.Title, p.CreationDate, u.DisplayName, p.Score
ORDER BY p.CreationDate DESC
LIMIT 10;

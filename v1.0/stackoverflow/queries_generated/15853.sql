SELECT p.Id AS PostId, 
       p.Title, 
       p.CreationDate, 
       u.DisplayName AS Author, 
       p.Score, 
       p.ViewCount
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
WHERE p.PostTypeId = 1 -- Only questions
ORDER BY p.CreationDate DESC
LIMIT 10;

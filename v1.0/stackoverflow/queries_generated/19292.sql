SELECT p.Id AS PostId, 
       p.Title, 
       u.DisplayName AS OwnerName, 
       p.CreationDate, 
       p.Score, 
       p.ViewCount, 
       c.Text AS CommentText 
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON p.Id = c.PostId
WHERE p.PostTypeId = 1  -- Only select questions
ORDER BY p.CreationDate DESC
LIMIT 10;

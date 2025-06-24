
SELECT TOP 10 p.Id, p.Title, p.CreationDate, u.DisplayName, p.Score, COUNT(c.Id) AS CommentCount
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON p.Id = c.PostId
WHERE p.PostTypeId = 1  
GROUP BY p.Id, p.Title, p.CreationDate, u.DisplayName, p.Score
ORDER BY p.CreationDate DESC;

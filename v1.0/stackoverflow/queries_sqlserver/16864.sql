
SELECT TOP 10 p.Title, u.DisplayName, p.CreationDate, p.Score, COUNT(c.Id) AS CommentCount
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON p.Id = c.PostId
WHERE p.PostTypeId = 1  
GROUP BY p.Title, u.DisplayName, p.CreationDate, p.Score
ORDER BY p.Score DESC, p.CreationDate DESC;

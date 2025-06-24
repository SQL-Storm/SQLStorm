
SELECT TOP 10 p.Title, p.CreationDate, u.DisplayName, COUNT(c.Id) AS CommentCount
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON p.Id = c.PostId
WHERE p.PostTypeId = 1
GROUP BY p.Title, p.CreationDate, u.DisplayName
ORDER BY p.CreationDate DESC;

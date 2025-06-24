
SELECT TOP 10 p.Id, p.Title, p.CreationDate, u.DisplayName, COUNT(c.Id) AS CommentCount
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON p.Id = c.PostId
WHERE p.PostTypeId = 1
GROUP BY p.Id, u.DisplayName, p.Title, p.CreationDate
ORDER BY p.CreationDate DESC;

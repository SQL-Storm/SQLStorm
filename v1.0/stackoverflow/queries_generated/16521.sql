SELECT p.Id, p.Title, p.CreationDate, u.DisplayName, p.ViewCount
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
WHERE p.PostTypeId = 1 -- only questions
ORDER BY p.CreationDate DESC
LIMIT 10;

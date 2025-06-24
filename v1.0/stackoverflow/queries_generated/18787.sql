SELECT p.Id, p.Title, u.DisplayName, p.CreationDate, p.Score
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
WHERE p.PostTypeId = 1 -- Select only Questions
ORDER BY p.Score DESC
LIMIT 10;

SELECT u.DisplayName, p.Title, p.CreationDate, p.Score, c.Text
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON p.Id = c.PostId
WHERE p.PostTypeId = 1 -- Only Questions
ORDER BY p.CreationDate DESC
LIMIT 10;

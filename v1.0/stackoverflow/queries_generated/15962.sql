SELECT p.Id, p.Title, p.CreationDate, u.DisplayName, p.Score
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
WHERE p.PostTypeId = 1 -- Only selecting questions
ORDER BY p.CreationDate DESC
LIMIT 10;

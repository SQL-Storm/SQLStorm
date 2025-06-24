SELECT p.Id, p.Title, p.CreationDate, u.DisplayName AS OwnerDisplayName, p.Score
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
WHERE p.PostTypeId = 1  -- Selecting only Questions
ORDER BY p.Score DESC
LIMIT 10;

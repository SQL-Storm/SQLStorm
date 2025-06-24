SELECT p.Id, p.Title, p.CreationDate, u.DisplayName AS Owner, p.Score
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
WHERE p.PostTypeId = 1  -- Only questions
ORDER BY p.Score DESC
LIMIT 10;

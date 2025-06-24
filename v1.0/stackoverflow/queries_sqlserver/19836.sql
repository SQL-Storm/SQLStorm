
SELECT TOP 10 u.DisplayName AS UserName, p.Title AS PostTitle, p.CreationDate, p.Score
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
WHERE p.PostTypeId = 1 
ORDER BY p.CreationDate DESC;

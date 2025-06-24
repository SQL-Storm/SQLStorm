
SELECT p.Title, p.CreationDate, u.DisplayName, t.TagName
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
JOIN Tags t ON p.Tags LIKE CONCAT('%', t.TagName, '%')
WHERE p.PostTypeId = 1 
GROUP BY p.Title, p.CreationDate, u.DisplayName, t.TagName
ORDER BY p.CreationDate DESC
LIMIT 10;

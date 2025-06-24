
SELECT TOP 10 u.Id AS UserId, u.DisplayName, p.Id AS PostId, p.Title, p.CreationDate
FROM Users u
JOIN Posts p ON u.Id = p.OwnerUserId
WHERE p.PostTypeId = 1
ORDER BY p.CreationDate DESC;


SELECT u.DisplayName, p.Title, ph.CreationDate
FROM Users u
JOIN Posts p ON u.Id = p.OwnerUserId
JOIN PostHistory ph ON p.Id = ph.PostId
WHERE ph.PostHistoryTypeId = 4 
GROUP BY u.DisplayName, p.Title, ph.CreationDate
ORDER BY ph.CreationDate DESC
LIMIT 10;

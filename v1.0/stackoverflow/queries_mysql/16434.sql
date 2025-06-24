
SELECT Users.DisplayName, Posts.Title, Posts.CreationDate
FROM Users
JOIN Posts ON Users.Id = Posts.OwnerUserId
WHERE Posts.PostTypeId = 1
GROUP BY Users.DisplayName, Posts.Title, Posts.CreationDate
ORDER BY Posts.CreationDate DESC
LIMIT 10;

SELECT U.DisplayName, P.Title, P.CreationDate
FROM Posts P
JOIN Users U ON P.OwnerUserId = U.Id
WHERE P.PostTypeId = 1 -- Filtering for Questions
ORDER BY P.CreationDate DESC
LIMIT 10;

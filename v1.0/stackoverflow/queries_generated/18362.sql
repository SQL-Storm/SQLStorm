SELECT P.Title, P.CreationDate, U.DisplayName AS OwnerName
FROM Posts P
JOIN Users U ON P.OwnerUserId = U.Id
WHERE P.PostTypeId = 1 -- Selecting only questions
ORDER BY P.CreationDate DESC
LIMIT 10;

SELECT U.DisplayName, P.Title, P.CreationDate, C.Text
FROM Posts P
JOIN Users U ON P.OwnerUserId = U.Id
LEFT JOIN Comments C ON P.Id = C.PostId
WHERE P.PostTypeId = 1 -- Questions only
ORDER BY P.CreationDate DESC
LIMIT 10;

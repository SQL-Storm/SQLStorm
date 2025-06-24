SELECT P.Title, P.CreationDate, U.DisplayName, COUNT(C.Id) AS CommentCount
FROM Posts P
JOIN Users U ON P.OwnerUserId = U.Id
LEFT JOIN Comments C ON P.Id = C.PostId
WHERE P.PostTypeId = 1 -- Filtering for questions
GROUP BY P.Id, U.DisplayName
ORDER BY P.CreationDate DESC
LIMIT 10;

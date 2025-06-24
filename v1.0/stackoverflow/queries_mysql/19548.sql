
SELECT P.Title, U.DisplayName, P.CreationDate, C.Text AS CommentText
FROM Posts P
JOIN Users U ON P.OwnerUserId = U.Id
LEFT JOIN Comments C ON P.Id = C.PostId
WHERE P.PostTypeId = 1 
GROUP BY P.Title, U.DisplayName, P.CreationDate, C.Text
ORDER BY P.CreationDate DESC
LIMIT 10;


SELECT TOP 10 P.Id AS PostId, 
       P.Title, 
       P.CreationDate, 
       P.Score, 
       U.DisplayName AS OwnerName, 
       COUNT(C.Id) AS CommentCount 
FROM Posts P
JOIN Users U ON P.OwnerUserId = U.Id
LEFT JOIN Comments C ON P.Id = C.PostId
WHERE P.PostTypeId = 1
GROUP BY P.Id, P.Title, P.CreationDate, P.Score, U.DisplayName
ORDER BY P.CreationDate DESC;

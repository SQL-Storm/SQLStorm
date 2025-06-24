
SELECT 
    U.Id AS UserId,
    U.DisplayName,
    U.Reputation,
    P.Id AS PostId,
    P.Title,
    P.CreationDate AS PostCreationDate,
    P.Score,
    P.ViewCount,
    P.AnswerCount,
    P.CommentCount
FROM 
    Users U
JOIN 
    Posts P ON U.Id = P.OwnerUserId
WHERE 
    U.Reputation > 0
GROUP BY 
    U.Id, 
    U.DisplayName, 
    U.Reputation, 
    P.Id, 
    P.Title, 
    P.CreationDate, 
    P.Score, 
    P.ViewCount, 
    P.AnswerCount, 
    P.CommentCount
ORDER BY 
    U.Reputation DESC, 
    P.CreationDate DESC
LIMIT 100;

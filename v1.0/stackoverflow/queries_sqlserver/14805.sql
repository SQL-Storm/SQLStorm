
SELECT 
    P.Id AS PostId,
    P.Title,
    P.PostTypeId,
    P.CreationDate,
    P.Score,
    P.ViewCount,
    P.AnswerCount,
    U.Id AS UserId,
    U.DisplayName AS OwnerDisplayName,
    U.Reputation,
    COUNT(V.Id) AS VoteCount,
    SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
FROM 
    Posts P
JOIN 
    Users U ON P.OwnerUserId = U.Id
LEFT JOIN 
    Votes V ON P.Id = V.PostId
GROUP BY 
    P.Id, P.Title, P.PostTypeId, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount, 
    U.Id, U.DisplayName, U.Reputation
ORDER BY 
    P.CreationDate DESC
OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY;

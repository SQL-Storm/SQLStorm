-- Performance benchmarking query to aggregate various metrics about posts, users, and votes
SELECT 
    P.Id AS PostId,
    P.Title,
    P.ViewCount,
    P.Score,
    P.CreationDate,
    U.DisplayName AS OwnerDisplayName,
    U.Reputation AS OwnerReputation,
    COUNT(DISTINCT C.Id) AS CommentCount,
    COUNT(DISTINCT V.Id) AS VoteCount,
    SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    SUM(CASE WHEN B.Id IS NOT NULL THEN 1 ELSE 0 END) AS BadgeCount
FROM 
    Posts P
JOIN 
    Users U ON P.OwnerUserId = U.Id
LEFT JOIN 
    Comments C ON P.Id = C.PostId
LEFT JOIN 
    Votes V ON P.Id = V.PostId
LEFT JOIN 
    Badges B ON U.Id = B.UserId
WHERE 
    P.CreationDate >= DATEADD(YEAR, -1, GETDATE()) -- Posts created in the last year
GROUP BY 
    P.Id, P.Title, P.ViewCount, P.Score, P.CreationDate, U.DisplayName, U.Reputation
ORDER BY 
    P.ViewCount DESC; -- Order by the most viewed posts

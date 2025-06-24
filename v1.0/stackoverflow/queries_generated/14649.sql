-- Performance benchmarking query to analyze post statistics
SELECT 
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.AnswerCount,
    p.CommentCount,
    U.DisplayName AS OwnerDisplayName,
    U.Reputation AS OwnerReputation,
    PHT.Name AS PostHistoryType,
    COUNT(PH.Id) AS HistoryChangeCount
FROM 
    Posts p
JOIN 
    Users U ON p.OwnerUserId = U.Id
LEFT JOIN 
    PostHistory PH ON p.Id = PH.PostId
LEFT JOIN 
    PostHistoryTypes PHT ON PH.PostHistoryTypeId = PHT.Id
WHERE 
    p.CreationDate >= '2023-01-01' -- Filter for posts created in the year 2023
GROUP BY 
    p.Id, U.DisplayName, U.Reputation, PHT.Name
ORDER BY 
    p.CreationDate DESC;

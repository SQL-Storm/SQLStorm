SELECT 
    P.Id AS PostId,
    P.CreationDate AS PostCreationDate,
    P.Score AS PostScore,
    U.Id AS UserId,
    U.DisplayName AS UserDisplayName,
    U.Reputation AS UserReputation,
    COUNT(DISTINCT C.Id) AS CommentCount,
    COUNT(DISTINCT CASE WHEN V.VoteTypeId = 2 THEN V.Id END) AS UpvoteCount,
    COUNT(DISTINCT CASE WHEN V.VoteTypeId = 3 THEN V.Id END) AS DownvoteCount,
    CASE 
        WHEN PH.PostHistoryTypeId = 10 THEN 'Closed'
        WHEN PH.PostHistoryTypeId = 11 THEN 'Reopened'
        ELSE 'Active'
    END AS PostStatus
FROM 
    Posts P
LEFT JOIN 
    Users U ON P.OwnerUserId = U.Id
LEFT JOIN 
    Comments C ON P.Id = C.PostId
LEFT JOIN 
    Votes V ON P.Id = V.PostId
LEFT JOIN 
    PostHistory PH ON P.Id = PH.PostId
GROUP BY 
    P.Id,
    P.CreationDate,
    P.Score,
    U.Id,
    U.DisplayName,
    U.Reputation,
    PH.PostHistoryTypeId
HAVING 
    COUNT(DISTINCT C.Id) > 5
ORDER BY 
    UpvoteCount DESC, PostCreationDate ASC
LIMIT 50;
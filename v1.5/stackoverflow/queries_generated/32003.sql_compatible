SELECT 
    P.Id AS PostId,
    P.CreationDate AS PostCreationDate,
    P.Score AS PostScore,
    U.Id AS UserId,
    U.DisplayName AS UserDisplayName,
    U.Reputation AS UserReputation,
    COUNT(DISTINCT C.Id) AS CommentCount,
    COUNT(DISTINCT V.Id) FILTER (WHERE V.VoteTypeId = 2) AS UpvoteCount,
    COUNT(DISTINCT V.Id) FILTER (WHERE V.VoteTypeId = 3) AS DownvoteCount,
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
    PH.PostHistoryTypeId,
    CASE 
        WHEN PH.PostHistoryTypeId = 10 THEN 'Closed'
        WHEN PH.PostHistoryTypeId = 11 THEN 'Reopened'
        ELSE 'Active'
    END
HAVING 
    COUNT(DISTINCT C.Id) > 5
ORDER BY 
    UpvoteCount DESC, P.CreationDate ASC
LIMIT 50;

WITH PostStats AS (
    SELECT 
        P.Id AS PostId,
        P.PostTypeId,
        P.CreationDate,
        P.ViewCount,
        P.Score,
        COUNT(CASE WHEN C.Id IS NOT NULL THEN 1 END) AS CommentCount,
        COUNT(DISTINCT V.UserId) AS VoteCount
    FROM 
        Posts P
    LEFT JOIN 
        Comments C ON P.Id = C.PostId
    LEFT JOIN 
        Votes V ON P.Id = V.PostId
    GROUP BY 
        P.Id, P.PostTypeId, P.CreationDate, P.ViewCount, P.Score
),
UserStats AS (
    SELECT 
        U.Id AS UserId,
        U.Reputation,
        COUNT(B.Id) AS BadgeCount,
        SUM(ISNULL(P.ViewCount, 0)) AS TotalPostViews,
        SUM(ISNULL(P.Score, 0)) AS TotalPostScore
    FROM 
        Users U
    LEFT JOIN 
        Badges B ON U.Id = B.UserId
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    GROUP BY 
        U.Id, U.Reputation
)
SELECT 
    PS.PostId,
    PS.PostTypeId,
    PS.CreationDate,
    PS.ViewCount,
    PS.Score,
    PS.CommentCount,
    PS.VoteCount,
    US.UserId,
    US.Reputation,
    US.BadgeCount,
    US.TotalPostViews,
    US.TotalPostScore
FROM 
    PostStats PS
JOIN 
    UserStats US ON PS.PostId = US.UserId
ORDER BY 
    PS.CreationDate DESC;

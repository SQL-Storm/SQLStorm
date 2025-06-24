
WITH UserVoteSummary AS (
    SELECT 
        U.Id AS UserId,
        U.Reputation,
        COUNT(CASE WHEN V.VoteTypeId = 2 THEN 1 END) AS UpVotes,
        COUNT(CASE WHEN V.VoteTypeId = 3 THEN 1 END) AS DownVotes,
        COUNT(*) AS TotalVotes
    FROM 
        Users U
    LEFT JOIN 
        Votes V ON U.Id = V.UserId
    GROUP BY 
        U.Id, U.Reputation
),
PostSummary AS (
    SELECT 
        P.Id AS PostId,
        P.OwnerUserId,
        P.PostTypeId,
        P.Title,
        COUNT(C) AS CommentCount,
        SUM(IFNULL(PV.VoteValue, 0)) AS Score,
        COUNT(DISTINCT B.Id) AS BadgeCount
    FROM 
        Posts P
    LEFT JOIN 
        Comments C ON P.Id = C.PostId
    LEFT JOIN 
        (SELECT 
            UserId,
            SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS VoteValue
         FROM 
            Votes 
         GROUP BY 
            UserId) PV ON PV.UserId = P.OwnerUserId
    LEFT JOIN 
        Badges B ON B.UserId = P.OwnerUserId
    WHERE 
        P.CreationDate >= NOW() - INTERVAL 1 YEAR
    GROUP BY 
        P.Id, P.OwnerUserId, P.PostTypeId, P.Title
),
FinalReport AS (
    SELECT 
        U.DisplayName,
        U.Location,
        US.Reputation,
        PS.Title,
        PS.CommentCount,
        PS.Score,
        IFNULL(PS.BadgeCount, 0) AS BadgeCount,
        @rank := IF(@prev_post = PS.PostId, @rank + 1, 1) AS Rank,
        @prev_post := PS.PostId
    FROM 
        UserVoteSummary US
    JOIN 
        Posts P ON US.UserId = P.OwnerUserId
    JOIN 
        PostSummary PS ON P.Id = PS.PostId
    JOIN 
        Users U ON P.OwnerUserId = U.Id,
        (SELECT @rank := 0, @prev_post := NULL) AS vars
)
SELECT 
    DisplayName,
    Location,
    Reputation,
    Title,
    CommentCount,
    Score,
    BadgeCount
FROM 
    FinalReport
WHERE 
    Rank = 1
ORDER BY 
    Score DESC, Reputation DESC
LIMIT 100;

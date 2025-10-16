WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.PostTypeId,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.Title,
        P.OwnerUserId,
        U.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.CreationDate) AS PostRank,
        COUNT(CASE WHEN V.VoteTypeId = 2 THEN 1 END) OVER (PARTITION BY P.Id) AS UpVotes,
        COUNT(CASE WHEN V.VoteTypeId = 3 THEN 1 END) OVER (PARTITION BY P.Id) AS DownVotes
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    LEFT JOIN 
        Votes V ON P.Id = V.PostId
    WHERE 
        P.PostTypeId IN (1, 2) AND P.ClosedDate IS NULL
),
TopUsers AS (
    SELECT 
        U.Id,
        U.DisplayName,
        U.Reputation,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        ROW_NUMBER() OVER (ORDER BY U.Reputation DESC, U.CreationDate) AS UserRank
    FROM 
        Users U
    LEFT JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id, U.DisplayName, U.Reputation, U.CreationDate
),
PostHistorySummary AS (
    SELECT 
        PH.PostId,
        COUNT(PH.Id) AS TotalEdits,
        MAX(CASE WHEN PH.PostHistoryTypeId = 5 THEN PH.CreationDate END) AS LastEditDate,
        STRING_AGG(DISTINCT CAST(PH.UserId AS VARCHAR(50)), ',') AS Editors
    FROM 
        PostHistory PH
    WHERE 
        PH.PostHistoryTypeId IN (5, 24)
    GROUP BY 
        PH.PostId
),
CommentActivity AS (
    SELECT 
        C.PostId,
        COUNT(C.Id) AS TotalComments,
        AVG(C.Score) AS AvgCommentScore
    FROM 
        Comments C
    GROUP BY 
        C.PostId
)
SELECT 
    RP.Id AS PostId,
    RP.PostTypeId,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.Title,
    RP.OwnerDisplayName,
    RP.PostRank,
    RP.UpVotes,
    RP.DownVotes,
    PHS.TotalEdits,
    PHS.LastEditDate,
    PHS.Editors,
    CA.TotalComments,
    CA.AvgCommentScore,
    U.DisplayName AS TopUser,
    U.Reputation,
    U.TotalBadges,
    U.GoldBadges,
    U.SilverBadges,
    U.BronzeBadges,
    U.UserRank
FROM 
    RankedPosts RP
LEFT JOIN 
    PostHistorySummary PHS ON RP.Id = PHS.PostId
LEFT JOIN 
    CommentActivity CA ON RP.Id = CA.PostId
LEFT JOIN 
    TopUsers U ON RP.OwnerUserId = U.Id
WHERE 
    RP.PostRank <= 10
ORDER BY 
    RP.Score DESC, RP.CreationDate;
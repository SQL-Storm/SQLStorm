WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.PostTypeId,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.OwnerUserId,
        U.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.CreationDate) AS PostRank
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId IN (1, 2) AND P.ClosedDate IS NULL
),
TopUsers AS (
    SELECT 
        U.Id,
        U.DisplayName,
        U.Reputation,
        COUNT(B.Id) AS BadgeCount,
        ROW_NUMBER() OVER (ORDER BY U.Reputation DESC, U.CreationDate) AS UserRank
    FROM 
        Users U
    LEFT JOIN 
        Badges B ON U.Id = B.UserId
    WHERE 
        U.Reputation > 1000
    GROUP BY 
        U.Id, U.DisplayName, U.Reputation
),
PostHistorySummary AS (
    SELECT 
        PH.PostId,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (1, 2, 3) THEN 1 END) AS InitialEdits,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 END) AS SubsequentEdits,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (10, 11) THEN 1 END) AS CloseReopenActions
    FROM 
        PostHistory PH
    GROUP BY 
        PH.PostId
),
CommentActivity AS (
    SELECT 
        C.PostId,
        COUNT(C.Id) AS CommentCount,
        AVG(C.Score) AS AvgCommentScore
    FROM 
        Comments C
    GROUP BY 
        C.PostId
),
TagUsage AS (
    SELECT 
        T.TagName,
        COUNT(P.Id) AS PostCount,
        MAX(P.CreationDate) AS LatestPostDate
    FROM 
        Tags T
    JOIN 
        Posts P ON T.WikiPostId = P.Id OR T.ExcerptPostId = P.Id
    GROUP BY 
        T.TagName
)
SELECT 
    RP.Id AS PostId,
    RP.PostTypeId,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.OwnerUserId,
    RP.OwnerDisplayName,
    RP.PostRank,
    TU.DisplayName AS TopUserDisplayName,
    TU.Reputation,
    TU.BadgeCount,
    TU.UserRank,
    PHS.InitialEdits,
    PHS.SubsequentEdits,
    PHS.CloseReopenActions,
    CA.CommentCount,
    CA.AvgCommentScore,
    TA.TagName,
    TA.PostCount,
    TA.LatestPostDate
FROM 
    RankedPosts RP
LEFT JOIN 
    TopUsers TU ON RP.OwnerUserId = TU.Id AND TU.UserRank <= 10
LEFT JOIN 
    PostHistorySummary PHS ON RP.Id = PHS.PostId
LEFT JOIN 
    CommentActivity CA ON RP.Id = CA.PostId
LEFT JOIN 
    TagUsage TA ON TRUE
WHERE 
    RP.PostRank <= 50
ORDER BY 
    RP.Score DESC, RP.CreationDate;
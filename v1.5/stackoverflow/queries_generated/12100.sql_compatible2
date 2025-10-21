WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.PostTypeId,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        U.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC) AS PostRank,
        DENSE_RANK() OVER (ORDER BY P.ViewCount DESC) AS ViewRank
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId IN (1, 2) AND P.CreationDate >= DATE '2024-10-01' - INTERVAL '1' YEAR
),
TopUsers AS (
    SELECT 
        U.Id,
        U.DisplayName,
        U.Reputation,
        COUNT(DISTINCT P.Id) AS PostCount,
        ROW_NUMBER() OVER (ORDER BY U.Reputation DESC, COUNT(DISTINCT P.Id) DESC) AS UserRank
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    WHERE 
        U.CreationDate >= DATE '2024-10-01' - INTERVAL '5' YEAR
    GROUP BY 
        U.Id, U.DisplayName, U.Reputation
),
TagStats AS (
    SELECT 
        T.TagName,
        COUNT(DISTINCT P.Id) AS PostCount,
        SUM(P.Score) AS TotalScore
    FROM 
        Tags T
    JOIN 
        Posts P ON T.WikiPostId = P.Id OR T.ExcerptPostId = P.Id
    WHERE 
        P.PostTypeId = 1
    GROUP BY 
        T.TagName
),
PostHistorySummary AS (
    SELECT 
        PH.PostId,
        COUNT(DISTINCT PH.PostHistoryTypeId) AS HistoryTypeCount,
        MAX(CASE WHEN PH.PostHistoryTypeId = 5 THEN PH.CreationDate END) AS LastEditDate
    FROM 
        PostHistory PH
    WHERE 
        PH.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6)
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
    WHERE 
        C.CreationDate >= DATE '2024-10-01' - INTERVAL '1' MONTH
    GROUP BY 
        C.PostId
)
SELECT 
    RP.Id AS PostId,
    RP.PostTypeId,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.OwnerDisplayName,
    RP.PostRank,
    RP.ViewRank,
    TU.DisplayName AS TopUser,
    TU.Reputation,
    TU.PostCount,
    TU.UserRank,
    TS.TagName,
    TS.PostCount AS TagPostCount,
    TS.TotalScore AS TagTotalScore,
    PHS.HistoryTypeCount,
    PHS.LastEditDate,
    CA.CommentCount,
    CA.AvgCommentScore
FROM 
    RankedPosts RP
LEFT JOIN 
    TopUsers TU ON RP.OwnerDisplayName = TU.DisplayName
LEFT JOIN 
    TagStats TS ON POSITION(TS.TagName IN RP.OwnerDisplayName) > 0
LEFT JOIN 
    PostHistorySummary PHS ON RP.Id = PHS.PostId
LEFT JOIN 
    CommentActivity CA ON RP.Id = CA.PostId
WHERE 
    RP.PostRank <= 10
    AND (TU.UserRank IS NULL OR TU.UserRank <= 10)
ORDER BY 
    RP.Score DESC, 
    RP.ViewCount DESC, 
    TU.Reputation DESC, 
    TS.TotalScore DESC;
WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.PostTypeId,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.OwnerUserId,
        U.DisplayName AS OwnerDisplayName,
        COUNT(C.Id) AS CommentCount,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC) AS PostRank,
        DENSE_RANK() OVER (ORDER BY P.ViewCount DESC) AS ViewRank
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    LEFT JOIN 
        Comments C ON P.Id = C.PostId
    WHERE 
        P.PostTypeId IN (1, 2)
    GROUP BY
        P.Id,
        P.PostTypeId,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.OwnerUserId,
        U.DisplayName
),
TopUsers AS (
    SELECT 
        U.Id,
        U.DisplayName,
        U.Reputation,
        COUNT(B.Id) AS BadgeCount,
        ROW_NUMBER() OVER (ORDER BY U.Reputation DESC) AS UserRank
    FROM 
        Users U
    LEFT JOIN 
        Badges B ON U.Id = B.UserId
    GROUP BY 
        U.Id, U.DisplayName, U.Reputation
),
PostHistorySummary AS (
    SELECT 
        PH.PostId,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6) THEN 1 END) AS EditCount,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15) THEN 1 END) AS StatusChangeCount
    FROM 
        PostHistory PH
    GROUP BY 
        PH.PostId
),
PostTagCounts AS (
    SELECT 
        P.Id,
        COUNT(T.Id) AS TagCount
    FROM 
        Posts P
    JOIN 
        Tags T ON P.Tags LIKE '%' || T.TagName || '%'
    GROUP BY 
        P.Id
)
SELECT 
    RP.Id,
    RP.PostTypeId,
    RP.CreationDate,
    RP.Score,
    RP.ViewCount,
    RP.OwnerUserId,
    RP.OwnerDisplayName,
    RP.CommentCount,
    RP.PostRank,
    RP.ViewRank,
    PHS.EditCount,
    PHS.StatusChangeCount,
    PTC.TagCount,
    (SELECT DisplayName FROM TopUsers WHERE Id = RP.OwnerUserId) AS TopUserDisplayName,
    (SELECT Reputation FROM TopUsers WHERE Id = RP.OwnerUserId) AS TopUserReputation
FROM 
    RankedPosts RP
JOIN 
    PostHistorySummary PHS ON RP.Id = PHS.PostId
JOIN 
    PostTagCounts PTC ON RP.Id = PTC.Id
WHERE 
    RP.PostRank <= 10
    AND PHS.EditCount > 0
    AND PTC.TagCount > 1
ORDER BY 
    RP.Score DESC, RP.ViewCount DESC;
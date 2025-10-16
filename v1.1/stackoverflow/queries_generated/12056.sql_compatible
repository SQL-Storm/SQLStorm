WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.PostTypeId,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.OwnerUserId,
        U.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.CreationDate) AS PostRank,
        P.Tags
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId IN (1, 2)
),
TopUsers AS (
    SELECT 
        U.Id,
        U.DisplayName,
        U.Reputation,
        COUNT(DISTINCT B.Id) AS BadgeCount,
        ROW_NUMBER() OVER (ORDER BY U.Reputation DESC, COUNT(DISTINCT B.Id) DESC) AS UserRank
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
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (2, 5, 24) THEN 1 END) AS EditCount,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (10, 11) THEN 1 END) AS CloseReopenCount,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate END) AS LastClosedDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN PH.CreationDate END) AS LastReopenedDate
    FROM 
        PostHistory PH
    GROUP BY 
        PH.PostId
),
TagUsage AS (
    SELECT 
        T.TagName,
        COUNT(DISTINCT P.Id) AS PostCount,
        SUM(P.ViewCount) AS TotalViews
    FROM 
        Tags T
    JOIN 
        Posts P ON T.WikiPostId = P.Id OR T.ExcerptPostId = P.Id
    GROUP BY 
        T.TagName
),
UserActivity AS (
    SELECT 
        U.Id,
        U.DisplayName,
        COUNT(DISTINCT C.Id) AS CommentCount,
        COUNT(DISTINCT V.Id) AS VoteCount,
        COUNT(DISTINCT P.Id) AS PostCount
    FROM 
        Users U
    LEFT JOIN 
        Comments C ON U.Id = C.UserId
    LEFT JOIN 
        Votes V ON U.Id = V.UserId
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    GROUP BY 
        U.Id, U.DisplayName
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
    TagUsage.TagName,
    TagUsage.PostCount AS TagPostCount,
    TagUsage.TotalViews AS TagTotalViews,
    TUA.CommentCount,
    TUA.VoteCount,
    TUA.PostCount AS UserPostCount,
    PHS.EditCount,
    PHS.CloseReopenCount,
    PHS.LastClosedDate,
    PHS.LastReopenedDate
FROM 
    RankedPosts RP
JOIN 
    TopUsers TUU ON RP.OwnerUserId = TUU.Id
JOIN 
    TagUsage ON
        -- Extract first tag from RP.Tags (format assumed like "<tag1><tag2>")
        CASE
            WHEN RP.Tags IS NULL THEN NULL
            WHEN POSITION('<' IN RP.Tags) = 0 THEN RP.Tags
            ELSE
                -- get substring between first '<' and next '>' if possible, otherwise fallback to whole Tags
                CASE
                    WHEN POSITION('>' IN RP.Tags) > POSITION('<' IN RP.Tags) THEN
                        SUBSTRING(RP.Tags FROM POSITION('<' IN RP.Tags)+1 FOR POSITION('>' IN RP.Tags)-POSITION('<' IN RP.Tags)-1)
                    ELSE RP.Tags
                END
        END = TagUsage.TagName
LEFT JOIN 
    UserActivity TUA ON RP.OwnerUserId = TUA.Id
LEFT JOIN 
    PostHistorySummary PHS ON RP.Id = PHS.PostId
WHERE 
    RP.PostRank <= 10
    AND TUU.UserRank <= 10
ORDER BY 
    RP.PostRank, TUU.UserRank;
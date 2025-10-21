WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.PostTypeId,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.OwnerUserId,
        U.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.CreationDate) AS UserRank,
        DENSE_RANK() OVER (ORDER BY P.Score DESC, P.CreationDate) AS GlobalRank
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId IN (1, 2)
),
TopUsers AS (
    SELECT 
        OwnerUserId,
        MAX(Score) AS MaxScore,
        COUNT(Id) AS PostCount
    FROM 
        RankedPosts
    WHERE 
        UserRank = 1
    GROUP BY 
        OwnerUserId
    HAVING 
        COUNT(Id) > 1
),
TagStats AS (
    SELECT 
        T.TagName,
        COUNT(P.Id) AS PostCount,
        AVG(P.Score) AS AvgScore
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
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COUNT(DISTINCT V.Id) AS TotalVotes,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN 
        Comments C ON U.Id = C.UserId
    LEFT JOIN 
        Votes V ON U.Id = V.UserId
    GROUP BY 
        U.Id, U.DisplayName
),
PostHistorySummary AS (
    SELECT 
        P.Id AS PostId,
        COUNT(DISTINCT PH.Id) AS TotalEdits,
        MAX(CASE WHEN PH.PostHistoryTypeId = 5 THEN PH.CreationDate END) AS LastEditDate
    FROM 
        Posts P
    LEFT JOIN 
        PostHistory PH ON P.Id = PH.PostId
    WHERE 
        P.PostTypeId IN (1, 2)
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
    RP.UserRank,
    RP.GlobalRank,
    TU.MaxScore,
    TU.PostCount AS UserTopPostCount,
    TS.TagName,
    TS.PostCount AS TagPostCount,
    TS.AvgScore AS TagAvgScore,
    UA.TotalPosts,
    UA.TotalComments,
    UA.TotalVotes,
    UA.UpVotes,
    UA.DownVotes,
    PHS.TotalEdits,
    PHS.LastEditDate
FROM 
    RankedPosts RP
LEFT JOIN 
    TopUsers TU ON RP.OwnerUserId = TU.OwnerUserId
LEFT JOIN 
    TagStats TS ON RP.OwnerUserId = RP.OwnerUserId
LEFT JOIN 
    UserActivity UA ON RP.OwnerUserId = UA.Id
LEFT JOIN 
    PostHistorySummary PHS ON RP.Id = PHS.PostId
WHERE 
    RP.GlobalRank <= 100
ORDER BY 
    RP.Score DESC, 
    RP.CreationDate;
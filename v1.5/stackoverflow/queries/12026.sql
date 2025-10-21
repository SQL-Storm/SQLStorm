WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.PostTypeId,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        U.DisplayName AS OwnerDisplayName,
        COUNT(V.Id) AS VoteCount,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.CreationDate) AS PostRank,
        P.OwnerUserId
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    LEFT JOIN 
        Votes V ON P.Id = V.PostId AND V.VoteTypeId IN (2, 3)
    WHERE 
        P.PostTypeId IN (1, 2) AND 
        P.ClosedDate IS NULL
    GROUP BY 
        P.Id, U.DisplayName, P.OwnerUserId, P.PostTypeId, P.Score, P.ViewCount, P.CreationDate
), 
TagStats AS (
    SELECT 
        T.TagName, 
        COUNT(P.Id) AS TagUsageCount, 
        AVG(P.Score) AS AvgTagScore
    FROM 
        Tags T
    JOIN 
        Posts P ON T.WikiPostId = P.Id OR T.ExcerptPostId = P.Id
    WHERE 
        P.PostTypeId = 1
    GROUP BY 
        T.TagName
), 
UserActivity AS (
    SELECT 
        U.Id, 
        U.DisplayName, 
        COUNT(P.Id) AS PostCount, 
        SUM(P.Score) AS TotalScore, 
        COUNT(C.Id) AS CommentCount
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN 
        Comments C ON U.Id = C.UserId
    WHERE 
        P.PostTypeId IN (1, 2) AND 
        (P.ClosedDate IS NULL OR P.ClosedDate IS NOT NULL)
    GROUP BY 
        U.Id, U.DisplayName
)
SELECT 
    RP.Id AS PostId, 
    RP.PostTypeId, 
    RP.Score, 
    RP.ViewCount, 
    RP.CreationDate, 
    RP.OwnerDisplayName, 
    RP.VoteCount, 
    RP.PostRank, 
    TS.TagName, 
    TS.TagUsageCount, 
    TS.AvgTagScore, 
    UA.DisplayName AS UserDisplayName, 
    UA.PostCount, 
    UA.TotalScore, 
    UA.CommentCount
FROM 
    RankedPosts RP
CROSS JOIN 
    TagStats TS
JOIN 
    UserActivity UA ON RP.OwnerUserId = UA.Id
WHERE 
    RP.PostRank <= 10 AND 
    UA.TotalScore > (SELECT AVG(TotalScore) FROM UserActivity)
ORDER BY 
    RP.Score DESC, 
    RP.CreationDate;
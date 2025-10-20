WITH RankedPosts AS (
    SELECT 
        P.Id, 
        P.PostTypeId, 
        P.Score, 
        P.ViewCount, 
        P.Title, 
        P.Tags, 
        P.CreationDate, 
        U.DisplayName AS OwnerDisplayName, 
        COUNT(V.Id) AS VoteCount,
        COUNT(C.Id) AS CommentCount,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.CreationDate) AS PostRank
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    LEFT JOIN 
        Votes V ON P.Id = V.PostId AND V.VoteTypeId IN (2, 3)
    LEFT JOIN 
        Comments C ON P.Id = C.PostId
    WHERE 
        P.PostTypeId IN (1, 2) -- Questions and Answers
    GROUP BY 
        P.Id, P.PostTypeId, P.Score, P.ViewCount, P.Title, P.Tags, P.CreationDate, U.DisplayName
), 
TagStats AS (
    SELECT 
        T.TagName, 
        COUNT(DISTINCT P.Id) AS TagUsageCount,
        AVG(P.Score) AS AvgTagScore
    FROM 
        Tags T
    JOIN 
        Posts P ON POSITION(T.TagName IN COALESCE(P.Tags, '')) > 0
    WHERE 
        P.PostTypeId IN (1, 2)
    GROUP BY 
        T.TagName
)
SELECT 
    RP.Id, 
    RP.PostTypeId, 
    RP.Score, 
    RP.ViewCount, 
    RP.Title, 
    RP.Tags, 
    RP.CreationDate, 
    RP.OwnerDisplayName, 
    RP.VoteCount, 
    RP.CommentCount, 
    RP.PostRank, 
    TS.TagName, 
    TS.TagUsageCount, 
    TS.AvgTagScore
FROM 
    RankedPosts RP
JOIN 
    TagStats TS ON RP.Tags IS NOT NULL AND POSITION(TS.TagName IN RP.Tags) > 0
WHERE 
    RP.PostRank <= 10
ORDER BY 
    RP.PostTypeId, 
    RP.Score DESC, 
    RP.CreationDate;
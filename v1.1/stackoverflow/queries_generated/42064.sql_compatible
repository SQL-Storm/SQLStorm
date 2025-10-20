WITH RankedPosts AS (
    SELECT 
        P.Id, 
        P.PostTypeId,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.OwnerUserId,
        U.Reputation,
        COUNT(C.Id) AS CommentCount,
        COUNT(V.Id) AS VoteCount,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.CreationDate) AS PostRank
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    LEFT JOIN 
        Comments C ON P.Id = C.PostId
    LEFT JOIN 
        Votes V ON P.Id = V.PostId
    WHERE 
        P.PostTypeId IN (1, 2)
        AND P.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
    GROUP BY 
        P.Id, P.PostTypeId, P.CreationDate, P.Score, P.ViewCount, P.OwnerUserId, U.Reputation
), 
TagStats AS (
    SELECT 
        T.TagName,
        COUNT(P.Id) AS TagUsageCount,
        AVG(P.Score) AS AvgTagScore
    FROM 
        Tags T
    JOIN 
        Posts P ON POSITION('<' || T.TagName || '>' IN P.Tags) > 0
    WHERE 
        P.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
    GROUP BY 
        T.TagName
)
SELECT 
    RP.PostTypeId,
    RP.CreationDate,
    RP.Score,
    RP.ViewCount,
    RP.OwnerUserId,
    RP.Reputation,
    RP.CommentCount,
    RP.VoteCount,
    RP.PostRank,
    TS.TagName,
    TS.TagUsageCount,
    TS.AvgTagScore
FROM 
    RankedPosts RP
JOIN 
    Posts P ON RP.Id = P.Id
JOIN 
    LATERAL (
      SELECT * FROM TagStats TS2
      WHERE POSITION('<' || TS2.TagName || '>' IN P.Tags) > 0
    ) TS ON true
WHERE 
    RP.PostRank <= 10
ORDER BY 
    RP.PostTypeId, 
    RP.Score DESC, 
    RP.CreationDate;
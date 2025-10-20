WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.PostTypeId,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.OwnerUserId,
        U.Reputation,
        U.DisplayName,
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
        P.PostTypeId IN (1, 2) AND
        P.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
    GROUP BY 
        P.Id, P.PostTypeId, P.CreationDate, P.Score, P.ViewCount, P.OwnerUserId, U.Reputation, U.DisplayName
), TopUsers AS (
    SELECT 
        U.Id,
        U.DisplayName,
        U.Reputation,
        COUNT(P.Id) AS PostCount,
        ROW_NUMBER() OVER (ORDER BY U.Reputation DESC, U.CreationDate) AS UserRank
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    WHERE 
        U.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
    GROUP BY 
        U.Id, U.DisplayName, U.Reputation, U.CreationDate
), TagStats AS (
    SELECT 
        T.Id AS TagId,
        T.TagName,
        COUNT(P.Id) AS PostCount,
        SUM(P.Score) AS TotalScore,
        ROW_NUMBER() OVER (ORDER BY COUNT(P.Id) DESC) AS TagRank
    FROM 
        Tags T
    JOIN 
        Posts P ON EXISTS (
            SELECT 1
            FROM UNNEST(string_to_array(P.Tags, '><')) AS tag(token)
            WHERE tag.token = CAST(T.Id AS text)
        )
    WHERE 
        P.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
    GROUP BY 
        T.Id, T.TagName
)
SELECT 
    RP.Id AS PostId,
    RP.PostTypeId,
    RP.CreationDate,
    RP.Score,
    RP.ViewCount,
    RP.OwnerUserId,
    TU.DisplayName AS OwnerDisplayName,
    TU.Reputation,
    RP.VoteCount,
    RP.CommentCount,
    RP.PostRank,
    TS.TagName,
    TS.PostCount AS TagPostCount,
    TS.TotalScore AS TagTotalScore
FROM 
    RankedPosts RP
JOIN 
    TopUsers TU ON RP.OwnerUserId = TU.Id
JOIN 
    Posts P ON RP.Id = P.Id
JOIN 
    Tags T ON EXISTS (
        SELECT 1
        FROM UNNEST(string_to_array(P.Tags, '><')) AS tag(token)
        WHERE tag.token = CAST(T.Id AS text)
    )
JOIN 
    TagStats TS ON T.TagName = TS.TagName
WHERE 
    RP.PostRank <= 100 AND
    TU.UserRank <= 100 AND
    TS.TagRank <= 50
ORDER BY 
    RP.Score DESC, 
    RP.CreationDate;
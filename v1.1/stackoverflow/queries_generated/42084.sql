-- {"query": "42084.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 688} 

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
        P.CreationDate >= NOW() - INTERVAL '1 year'
    GROUP BY 
        P.Id, U.Id
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
        U.CreationDate >= NOW() - INTERVAL '1 year'
    GROUP BY 
        U.Id
), TagStats AS (
    SELECT 
        T.TagName,
        COUNT(P.Id) AS PostCount,
        SUM(P.Score) AS TotalScore,
        ROW_NUMBER() OVER (ORDER BY COUNT(P.Id) DESC) AS TagRank
    FROM 
        Tags T
    JOIN 
        Posts P ON T.Id = ANY(string_to_array(P.Tags, '><'))
    WHERE 
        P.CreationDate >= NOW() - INTERVAL '1 year'
    GROUP BY 
        T.Id
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
    Tags T ON P.Id = ANY(string_to_array(T.Tags, '><'))
JOIN 
    TagStats TS ON T.TagName = TS.TagName
WHERE 
    RP.PostRank <= 100 AND
    TU.UserRank <= 100 AND
    TS.TagRank <= 50
ORDER BY 
    RP.Score DESC, 
    RP.CreationDate;

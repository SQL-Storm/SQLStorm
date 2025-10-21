-- {"query": "42064.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 482} 

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
        P.PostTypeId IN (1, 2) AND
        P.CreationDate >= NOW() - INTERVAL '1 year'
    GROUP BY 
        P.Id, U.Reputation
), 
TagStats AS (
    SELECT 
        T.TagName,
        COUNT(P.Id) AS TagUsageCount,
        AVG(P.Score) AS AvgTagScore
    FROM 
        Tags T
    JOIN 
        Posts P ON T.Id = ANY(string_to_array(P.Tags, ''><''))
    WHERE 
        P.CreationDate >= NOW() - INTERVAL '1 year'
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
    LATERAL (SELECT * FROM TagStats WHERE TagName = ANY(string_to_array(P.Tags, ''><''))) TS ON true
WHERE 
    RP.PostRank <= 10
ORDER BY 
    RP.PostTypeId, 
    RP.Score DESC, 
    RP.CreationDate;

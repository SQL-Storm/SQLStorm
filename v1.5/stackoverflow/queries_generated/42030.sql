-- {"query": "42030.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 755} 

WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.PostTypeId,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        U.DisplayName AS OwnerDisplayName,
        U.Reputation AS OwnerReputation,
        COUNT(V.Id) FILTER (WHERE V.VoteTypeId = 2) AS UpVotes,
        COUNT(V.Id) FILTER (WHERE V.VoteTypeId = 3) AS DownVotes,
        COUNT(C.Id) AS CommentCount,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.CreationDate) AS PostRank
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    LEFT JOIN 
        Votes V ON P.Id = V.PostId
    LEFT JOIN 
        Comments C ON P.Id = C.PostId
    WHERE 
        P.PostTypeId IN (1, 2) AND P.ClosedDate IS NULL
    GROUP BY 
        P.Id, U.DisplayName, U.Reputation
), TagStats AS (
    SELECT 
        T.TagName,
        COUNT(P.Id) AS TagUsageCount,
        AVG(P.Score) AS AvgTagScore
    FROM 
        Tags T
    JOIN 
        Posts P ON string_to_array(P.Tags, ''><'') @> ARRAY[T.TagName]
    WHERE 
        P.PostTypeId = 1 AND P.ClosedDate IS NULL
    GROUP BY 
        T.TagName
), UserActivity AS (
    SELECT 
        U.Id,
        U.DisplayName,
        U.Reputation,
        COUNT(P.Id) AS PostsCount,
        COUNT(C.Id) AS CommentsCount,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN 
        Comments C ON U.Id = C.UserId
    LEFT JOIN 
        Votes V ON U.Id = V.UserId
    WHERE 
        P.PostTypeId IN (1, 2) AND P.ClosedDate IS NULL
    GROUP BY 
        U.Id, U.DisplayName, U.Reputation
)
SELECT 
    RP.Id AS PostId,
    RP.PostTypeId,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.OwnerDisplayName,
    RP.OwnerReputation,
    RP.UpVotes,
    RP.DownVotes,
    RP.CommentCount,
    RP.PostRank,
    TS.TagName,
    TS.TagUsageCount,
    TS.AvgTagScore,
    UA.Id AS UserId,
    UA.DisplayName AS UserDisplayName,
    UA.Reputation AS UserReputation,
    UA.PostsCount,
    UA.CommentsCount,
    UA.TotalUpVotes
FROM 
    RankedPosts RP
JOIN 
    TagStats TS ON string_to_array(RP.Tags, ''><'') @> ARRAY[TS.TagName]
JOIN 
    UserActivity UA ON RP.OwnerUserId = UA.Id
WHERE 
    RP.PostRank <= 10
ORDER BY 
    RP.PostTypeId, RP.Score DESC, RP.CreationDate;

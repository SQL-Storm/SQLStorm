-- {"query": "42005.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 566} 

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
        COUNT(C.Id) AS CommentCount, 
        COUNT(DISTINCT V.UserId) AS UniqueVotersCount,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.CreationDate) AS PostRank
    FROM 
        Posts P
    JOIN 
        Users U ON P.OwnerUserId = U.Id
    LEFT JOIN 
        Comments C ON P.Id = C.PostId
    LEFT JOIN 
        Votes V ON P.Id = V.PostId
    WHERE 
        P.PostTypeId IN (1, 2) AND P.CreationDate > CURRENT_DATE - INTERVAL '1 year'
    GROUP BY 
        P.Id, U.Id
), 
TopPosts AS (
    SELECT 
        Id, 
        PostTypeId, 
        CreationDate, 
        Score, 
        ViewCount, 
        OwnerUserId, 
        Reputation, 
        DisplayName, 
        CommentCount, 
        UniqueVotersCount
    FROM 
        RankedPosts
    WHERE 
        PostRank <= 10
)
SELECT 
    TP.Id, 
    TP.PostTypeId, 
    TP.CreationDate, 
    TP.Score, 
    TP.ViewCount, 
    TP.OwnerUserId, 
    TP.Reputation, 
    TP.DisplayName, 
    TP.CommentCount, 
    TP.UniqueVotersCount, 
    COUNT(PH.Id) AS EditCount,
    STRING_AGG(DISTINCT T.TagName, ', ') AS Tags
FROM 
    TopPosts TP
LEFT JOIN 
    PostHistory PH ON TP.Id = PH.PostId AND PH.PostHistoryTypeId IN (3, 5, 6, 24)
JOIN 
    Posts P ON TP.Id = P.Id
JOIN 
    LATERAL REGEXP_SPLIT_TO_TABLE(P.Tags, ''><'') AS Tag ON TRUE
JOIN 
    Tags T ON Tag = T.TagName
GROUP BY 
    TP.Id, TP.PostTypeId, TP.CreationDate, TP.Score, TP.ViewCount, TP.OwnerUserId, TP.Reputation, TP.DisplayName, TP.CommentCount, TP.UniqueVotersCount
ORDER BY 
    TP.Score DESC, TP.CreationDate;

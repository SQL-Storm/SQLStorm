-- {"query": "12065.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 791} 

WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.PostTypeId,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.OwnerUserId,
        U.DisplayName,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.CreationDate) AS PostRank
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId IN (1, 2) AND P.Score > 0
),
TopUsers AS (
    SELECT 
        U.Id,
        U.DisplayName,
        U.Reputation,
        COUNT(DISTINCT P.Id) AS PostCount,
        ROW_NUMBER() OVER (ORDER BY U.Reputation DESC, U.CreationDate) AS UserRank
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    WHERE 
        P.PostTypeId IN (1, 2) AND P.Score > 0
    GROUP BY 
        U.Id, U.DisplayName, U.Reputation
),
TagStats AS (
    SELECT 
        T.TagName,
        COUNT(DISTINCT P.Id) AS PostCount,
        SUM(P.Score) AS TotalScore
    FROM 
        Tags T
    LEFT JOIN 
        Posts P ON T.TagName = ANY(string_to_array(P.Tags, '<'))
    WHERE 
        P.PostTypeId = 1
    GROUP BY 
        T.TagName
),
PostHistorySummary AS (
    SELECT 
        PH.PostId,
        COUNT(DISTINCT PH.Id) AS RevisionCount,
        MAX(CASE WHEN PH.PostHistoryTypeId = 5 THEN PH.CreationDate END) AS LastEditDate
    FROM 
        PostHistory PH
    GROUP BY 
        PH.PostId
),
UserActivity AS (
    SELECT 
        U.Id,
        U.DisplayName,
        COUNT(DISTINCT C.Id) AS CommentCount,
        COUNT(DISTINCT V.Id) AS VoteCount
    FROM 
        Users U
    LEFT JOIN 
        Comments C ON U.Id = C.UserId
    LEFT JOIN 
        Votes V ON U.Id = V.UserId
    WHERE 
        C.CreationDate > (CURRENT_DATE - INTERVAL '30 days') OR V.CreationDate > (CURRENT_DATE - INTERVAL '30 days')
    GROUP BY 
        U.Id, U.DisplayName
)
SELECT 
    RP.Id,
    RP.PostTypeId,
    RP.Score,
    RP.ViewCount,
    RP.CreationDate,
    RP.OwnerUserId,
    RP.DisplayName,
    RP.PostRank,
    TU.Reputation,
    TU.PostCount,
    TU.UserRank,
    TS.TagName,
    TS.PostCount AS TagPostCount,
    TS.TotalScore AS TagTotalScore,
    PHIS.RevisionCount,
    PHIS.LastEditDate,
    UA.CommentCount,
    UA.VoteCount
FROM 
    RankedPosts RP
JOIN 
    TopUsers TU ON RP.OwnerUserId = TU.Id
JOIN 
    TagStats TS ON RP.Tags LIKE '%' || TS.TagName || '%'
LEFT JOIN 
    PostHistorySummary PHIS ON RP.Id = PHIS.PostId
LEFT JOIN 
    UserActivity UA ON RP.OwnerUserId = UA.Id
WHERE 
    RP.PostRank <= 10 AND TU.UserRank <= 10
ORDER BY 
    RP.Score DESC, RP.CreationDate;

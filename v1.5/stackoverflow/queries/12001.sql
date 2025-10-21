-- {"query": "12001.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 855} 
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
        UserRank <= 3
    GROUP BY 
        OwnerUserId
    HAVING 
        COUNT(Id) > 1
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
    GROUP BY 
        T.TagName
),
UserActivity AS (
    SELECT 
        U.Id,
        U.DisplayName,
        COUNT(DISTINCT P.Id) AS PostCount,
        COUNT(DISTINCT C.Id) AS CommentCount,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount
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
        PH.PostId,
        COUNT(PH.Id) AS EditCount,
        MAX(CASE WHEN PH.PostHistoryTypeId = 5 THEN PH.CreationDate END) AS LastEditBodyDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 6 THEN PH.CreationDate END) AS LastEditTagsDate
    FROM 
        PostHistory PH
    GROUP BY 
        PH.PostId
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
    TU.PostCount AS TopUserPostCount,
    TS.TagName,
    TS.TagUsageCount,
    TS.AvgTagScore,
    UA.PostCount AS UserPostCount,
    UA.CommentCount,
    UA.UpVoteCount,
    UA.DownVoteCount,
    PHS.EditCount,
    PHS.LastEditBodyDate,
    PHS.LastEditTagsDate
FROM 
    RankedPosts RP
JOIN 
    TopUsers TU ON RP.OwnerUserId = TU.OwnerUserId
JOIN 
    TagStats TS ON RP.Id IN (
        SELECT 
            P.Id
        FROM 
            Posts P
        JOIN 
            Tags T ON P.Tags LIKE '%' || T.TagName || '%'
        WHERE 
            T.TagName = TS.TagName
    )
JOIN 
    UserActivity UA ON RP.OwnerUserId = UA.Id
LEFT JOIN 
    PostHistorySummary PHS ON RP.Id = PHS.PostId
WHERE 
    RP.GlobalRank <= 100
ORDER BY 
    RP.Score DESC, 
    RP.CreationDate;
-- {"query": "12063.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 905} 
WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.PostTypeId,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.OwnerUserId,
        U.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.CreationDate) AS UserRank
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
        SUM(P.Score) AS TotalScore,
        AVG(P.Score) AS AvgScore
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
        P.Id AS PostId,
        COUNT(PH.Id) AS EditCount,
        MAX(CASE WHEN PH.PostHistoryTypeId = 5 THEN PH.CreationDate ELSE NULL END) AS LastEditBodyDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 6 THEN PH.CreationDate ELSE NULL END) AS LastEditTagsDate
    FROM 
        Posts P
    LEFT JOIN 
        PostHistory PH ON P.Id = PH.PostId
    WHERE 
        PH.PostHistoryTypeId IN (5, 6)
    GROUP BY 
        P.Id
),
PostWithHistory AS (
    SELECT 
        P.Id,
        P.Title,
        P.Tags,
        P.Score,
        P.ViewCount,
        PHS.EditCount,
        PHS.LastEditBodyDate,
        PHS.LastEditTagsDate
    FROM 
        Posts P
    JOIN 
        PostHistorySummary PHS ON P.Id = PHS.PostId
)
SELECT 
    UA.DisplayName,
    UA.PostCount,
    UA.CommentCount,
    UA.UpVoteCount,
    UA.DownVoteCount,
    TU.MaxScore,
    TU.PostCount AS TopPostCount,
    TS.TagName,
    TS.TagUsageCount,
    TS.TotalScore,
    TS.AvgScore,
    PWH.Title,
    PWH.Tags,
    PWH.Score,
    PWH.ViewCount,
    PWH.EditCount,
    PWH.LastEditBodyDate,
    PWH.LastEditTagsDate
FROM 
    UserActivity UA
JOIN 
    TopUsers TU ON UA.Id = TU.OwnerUserId
JOIN 
    TagStats TS ON 1=1
JOIN 
    PostWithHistory PWH ON UA.Id = PWH.Id
WHERE 
    UA.PostCount > 10
    AND TS.TagUsageCount > 50
ORDER BY 
    UA.UpVoteCount DESC, 
    PWH.Score DESC, 
    TS.AvgScore DESC
LIMIT 100;
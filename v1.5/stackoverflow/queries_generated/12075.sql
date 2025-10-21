-- {"query": "12075.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 806} 

WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.PostTypeId,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.OwnerUserId,
        U.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.CreationDate) AS UserPostRank
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId IN (1, 2) AND P.Score > 0 AND P.CreationDate > CURRENT_DATE - INTERVAL '1 year'
), 
TagCounts AS (
    SELECT 
        T.TagName,
        COUNT(DISTINCT P.Id) AS PostCount
    FROM 
        Tags T
    JOIN 
        Posts P ON T.WikiPostId = P.Id OR T.ExcerptPostId = P.Id
    WHERE 
        P.CreationDate > CURRENT_DATE - INTERVAL '1 year'
    GROUP BY 
        T.TagName
), 
UserActivity AS (
    SELECT 
        U.Id,
        U.DisplayName,
        COUNT(DISTINCT P.Id) AS PostCount,
        SUM(P.Score) AS TotalScore,
        COUNT(DISTINCT C.Id) AS CommentCount,
        COUNT(DISTINCT V.Id) AS VoteCount
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN 
        Comments C ON U.Id = C.UserId
    LEFT JOIN 
        Votes V ON U.Id = V.UserId
    WHERE 
        P.CreationDate > CURRENT_DATE - INTERVAL '1 year' OR C.CreationDate > CURRENT_DATE - INTERVAL '1 year' OR V.CreationDate > CURRENT_DATE - INTERVAL '1 year'
    GROUP BY 
        U.Id, U.DisplayName
), 
PostHistorySummary AS (
    SELECT 
        PH.PostId,
        COUNT(DISTINCT PH.Id) AS RevisionCount,
        MAX(CASE WHEN PH.PostHistoryTypeId = 5 THEN PH.CreationDate END) AS LastEditDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate END) AS CloseDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN PH.CreationDate END) AS ReopenDate
    FROM 
        PostHistory PH
    WHERE 
        PH.CreationDate > CURRENT_DATE - INTERVAL '1 year'
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
    RP.UserPostRank,
    TC.TagName,
    TC.PostCount AS TagPostCount,
    UA.PostCount AS UserPostCount,
    UA.TotalScore AS UserTotalScore,
    UA.CommentCount AS UserCommentCount,
    UA.VoteCount AS UserVoteCount,
    PHS.RevisionCount,
    PHS.LastEditDate,
    PHS.CloseDate,
    PHS.ReopenDate
FROM 
    RankedPosts RP
LEFT JOIN 
    TagCounts TC ON SPLIT_PART(RP.Tags, '<', 2) = TC.TagName
LEFT JOIN 
    UserActivity UA ON RP.OwnerUserId = UA.Id
LEFT JOIN 
    PostHistorySummary PHS ON RP.Id = PHS.PostId
WHERE 
    RP.UserPostRank <= 3
ORDER BY 
    RP.Score DESC, 
    RP.CreationDate;

WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.PostTypeId,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.OwnerUserId,
        U.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.CreationDate) AS UserPostRank,
        P.Tags
    FROM 
        Posts P
    LEFT JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId IN (1, 2)
),
TopPosts AS (
    SELECT 
        Id,
        PostTypeId,
        Score,
        ViewCount,
        CreationDate,
        OwnerUserId,
        OwnerDisplayName,
        Tags
    FROM 
        RankedPosts
    WHERE 
        UserPostRank <= 3
),
AggregatedData AS (
    SELECT 
        T.TagName,
        COUNT(DISTINCT P.Id) AS PostCount,
        AVG(P.Score) AS AvgScore,
        SUM(P.ViewCount) AS TotalViews
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
        COUNT(DISTINCT PH.Id) AS RevisionCount,
        MAX(CASE WHEN PH.PostHistoryTypeId = 5 THEN PH.CreationDate END) AS LastEditBodyDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 6 THEN PH.CreationDate END) AS LastEditTagsDate
    FROM 
        Posts P
    LEFT JOIN 
        PostHistory PH ON P.Id = PH.PostId
    WHERE 
        P.PostTypeId IN (1, 2)
    GROUP BY 
        P.Id
)
SELECT 
    TP.Id,
    TP.PostTypeId,
    TP.Score,
    TP.ViewCount,
    TP.CreationDate,
    TP.OwnerUserId,
    TP.OwnerDisplayName,
    AD.TagName,
    AD.PostCount AS TagPostCount,
    AD.AvgScore AS TagAvgScore,
    AD.TotalViews AS TagTotalViews,
    UA.PostCount AS UserPostCount,
    UA.CommentCount AS UserCommentCount,
    UA.UpVoteCount AS UserUpVoteCount,
    UA.DownVoteCount AS UserDownVoteCount,
    PHS.RevisionCount,
    PHS.LastEditBodyDate,
    PHS.LastEditTagsDate
FROM 
    TopPosts TP
JOIN 
    AggregatedData AD ON EXISTS (
        SELECT 1
        WHERE TP.Tags IS NOT NULL
          AND POSITION(('<' || AD.TagName || '>') IN TP.Tags) > 0
    )
JOIN 
    UserActivity UA ON TP.OwnerUserId = UA.Id
LEFT JOIN 
    PostHistorySummary PHS ON TP.Id = PHS.PostId
ORDER BY 
    TP.Score DESC, 
    TP.CreationDate;
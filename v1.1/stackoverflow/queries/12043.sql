WITH RankedPosts AS (
    SELECT 
        P.Id,
        P.PostTypeId,
        P.Score,
        P.ViewCount,
        P.CreationDate,
        P.OwnerUserId,
        U.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.CreationDate) AS UserPostRank
    FROM 
        Posts P
    JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.PostTypeId IN (1, 2)
),
TopPosts AS (
    SELECT 
        P.Id, 
        P.PostTypeId, 
        P.Score, 
        P.ViewCount, 
        P.CreationDate, 
        P.OwnerUserId, 
        U.DisplayName AS OwnerDisplayName,
        P.Tags
    FROM 
        RankedPosts RP
    JOIN
        Posts P ON RP.Id = P.Id
    JOIN
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        RP.UserPostRank = 1
),
TagStats AS (
    SELECT 
        T.TagName,
        COUNT(P.Id) AS PostCount,
        AVG(P.Score) AS AvgScore,
        MAX(P.CreationDate) AS LatestPostDate
    FROM 
        Tags T
    JOIN 
        Posts P ON T.WikiPostId = P.Id OR T.ExcerptPostId = P.Id
    GROUP BY 
        T.TagName
),
UserActivity AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        COUNT(DISTINCT P.Id) AS PostCount,
        COUNT(DISTINCT C.Id) AS CommentCount,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCount,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteCount
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
        MAX(CASE WHEN PH.PostHistoryTypeId = 5 THEN PH.CreationDate END) AS LastEditDate
    FROM 
        Posts P
    LEFT JOIN 
        PostHistory PH ON P.Id = PH.PostId
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
    UA.PostCount AS UserTotalPostCount,
    UA.CommentCount AS UserCommentCount,
    UA.UpvoteCount AS UserUpvoteCount,
    UA.DownvoteCount AS UserDownvoteCount,
    PHS.RevisionCount,
    PHS.LastEditDate,
    TS.TagName,
    TS.PostCount AS TagPostCount,
    TS.AvgScore AS TagAvgScore,
    TS.LatestPostDate AS TagLatestPostDate
FROM 
    TopPosts TP
JOIN 
    UserActivity UA ON TP.OwnerUserId = UA.UserId
LEFT JOIN 
    PostHistorySummary PHS ON TP.Id = PHS.PostId
LEFT JOIN LATERAL (
    SELECT 
        t.TagName,
        ts.PostCount,
        ts.AvgScore,
        ts.LatestPostDate
    FROM (
        SELECT
            TRIM(tag) AS tag
        FROM
            (SELECT REGEXP_SPLIT_TO_TABLE(TP.Tags, '<') AS tag) sub
        WHERE TRIM(sub.tag) <> ''
    ) split_tags
    JOIN Tags t ON split_tags.tag = t.TagName
    JOIN TagStats ts ON t.TagName = ts.TagName
    ORDER BY ts.PostCount DESC
    LIMIT 1
) TS ON TRUE
ORDER BY 
    TP.Score DESC, 
    TP.CreationDate;
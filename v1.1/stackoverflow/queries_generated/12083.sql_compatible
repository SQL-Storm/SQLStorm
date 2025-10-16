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
        P.PostTypeId IN (1, 2)
),
TopPosts AS (
    SELECT 
        Id, 
        PostTypeId, 
        CreationDate, 
        Score, 
        ViewCount, 
        OwnerUserId, 
        OwnerDisplayName
    FROM 
        RankedPosts
    WHERE 
        UserPostRank <= 3
),
AggregatedData AS (
    SELECT 
        T.TagName,
        COUNT(DISTINCT P.Id) AS PostCount,
        SUM(P.Score) AS TotalScore,
        AVG(P.Score) AS AvgScore,
        MAX(P.CreationDate) AS LatestPostDate,
        T.WikiPostId
    FROM 
        Tags T
    JOIN 
        Posts P ON T.WikiPostId = P.Id
    WHERE 
        P.PostTypeId = 1
    GROUP BY 
        T.TagName, T.WikiPostId
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
        P.Title,
        COUNT(DISTINCT PH.Id) AS RevisionCount,
        MAX(CASE WHEN PH.PostHistoryTypeId = 5 THEN PH.CreationDate END) AS LastEditDate
    FROM 
        Posts P
    LEFT JOIN 
        PostHistory PH ON P.Id = PH.PostId
    GROUP BY 
        P.Id, P.Title
)
SELECT 
    TP.Id AS TopPostId,
    TP.PostTypeId,
    TP.CreationDate AS TopPostCreationDate,
    TP.Score AS TopPostScore,
    AD.TagName,
    AD.PostCount AS TagPostCount,
    AD.TotalScore AS TagTotalScore,
    UA.UserId,
    UA.DisplayName AS UserDisplayName,
    UA.PostCount AS UserPostCount,
    UA.CommentCount AS UserCommentCount,
    UA.UpvoteCount,
    UA.DownvoteCount,
    PHS.RevisionCount,
    PHS.LastEditDate
FROM 
    TopPosts TP
JOIN 
    AggregatedData AD ON TP.Id = AD.WikiPostId
JOIN 
    UserActivity UA ON TP.OwnerUserId = UA.UserId
LEFT JOIN 
    PostHistorySummary PHS ON TP.Id = PHS.PostId
WHERE 
    TP.Score > (
        SELECT AVG(P2.Score) 
        FROM Posts P2 
        WHERE P2.PostTypeId = TP.PostTypeId
    )
GROUP BY
    TP.Id,
    TP.PostTypeId,
    TP.CreationDate,
    TP.Score,
    TP.ViewCount,
    TP.OwnerUserId,
    TP.OwnerDisplayName,
    AD.TagName,
    AD.PostCount,
    AD.TotalScore,
    AD.AvgScore,
    AD.LatestPostDate,
    AD.WikiPostId,
    UA.UserId,
    UA.DisplayName,
    UA.PostCount,
    UA.CommentCount,
    UA.UpvoteCount,
    UA.DownvoteCount,
    PHS.RevisionCount,
    PHS.LastEditDate
ORDER BY 
    TP.Score DESC, 
    AD.TotalScore DESC, 
    UA.UpvoteCount DESC;
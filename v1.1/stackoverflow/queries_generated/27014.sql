-- {"query": "27014.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2337, "output_tokens": 1491} 

WITH UserActivity AS (
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.DisplayName,
        U.Views,
        U.UpVotes,
        U.DownVotes,
        COUNT(P.Id) AS TotalPosts,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COUNT(DISTINCT V.Id) AS TotalVotes,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        MAX(P.CreationDate) AS LastPostDate,
        MAX(C.CreationDate) AS LastCommentDate,
        MAX(V.CreationDate) AS LastVoteDate,
        MAX(B.Date) AS LastBadgeDate
    FROM
        Users U
    LEFT JOIN
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN
        Comments C ON U.Id = C.UserId
    LEFT JOIN
        Votes V ON U.Id = V.UserId
    LEFT JOIN
        Badges B ON U.Id = B.UserId
    GROUP BY
        U.Id, U.Reputation, U.DisplayName, U.Views, U.UpVotes, U.DownVotes
),
PostMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.OwnerUserId,
        P.LastActivityDate,
        U.DisplayName AS OwnerDisplayName,
        COALESCE(A.Id, -1) AS AcceptedAnswerId,
        COALESCE(PH.PostHistoryTypeId, -1) AS LatestPostHistoryTypeId,
        COALESCE(PH.CreationDate, P.CreationDate) AS LatestPostHistoryDate,
        COALESCE(PH.UserId, -1) AS LatestPostHistoryUserId,
        COUNT(DISTINCT V.Id) AS TotalVotes,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COUNT(DISTINCT L.Id) AS TotalLinks,
        STRING_AGG(T.TagName, '><') AS TagsList
    FROM
        Posts P
    LEFT JOIN
        Users U ON P.OwnerUserId = U.Id
    LEFT JOIN
        Posts A ON P.AcceptedAnswerId = A.Id
    LEFT JOIN
        PostHistory PH ON P.Id = PH.PostId
    LEFT JOIN
        Votes V ON P.Id = V.PostId
    LEFT JOIN
        Comments C ON P.Id = C.PostId
    LEFT JOIN
        PostLinks L ON P.Id = L.PostId
    LEFT JOIN
        Tags T ON P.Tags LIKE CONCAT('%<', T.TagName, '>%')
    GROUP BY
        P.Id, P.PostTypeId, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount,
        P.CommentCount, P.FavoriteCount, P.OwnerUserId, P.LastActivityDate,
        U.DisplayName, A.Id, PH.PostHistoryTypeId, PH.CreationDate, PH.UserId
),
ActiveUsers AS (
    SELECT
        UserId,
        Reputation,
        DisplayName,
        Views,
        UpVotes,
        DownVotes,
        TotalPosts,
        TotalComments,
        TotalVotes,
        TotalBadges,
        LastPostDate,
        LastCommentDate,
        LastVoteDate,
        LastBadgeDate,
        DENSE_RANK() OVER (ORDER BY LastPostDate DESC, LastCommentDate DESC, LastVoteDate DESC, LastBadgeDate DESC) AS ActivityRank
    FROM
        UserActivity
    WHERE
        LastPostDate IS NOT NULL OR
        LastCommentDate IS NOT NULL OR
        LastVoteDate IS NOT NULL OR
        LastBadgeDate IS NOT NULL
),
TopPosts AS (
    SELECT
        PostId,
        PostTypeId,
        CreationDate,
        Score,
        ViewCount,
        AnswerCount,
        CommentCount,
        FavoriteCount,
        OwnerUserId,
        OwnerDisplayName,
        AcceptedAnswerId,
        LatestPostHistoryTypeId,
        LatestPostHistoryDate,
        LatestPostHistoryUserId,
        TotalVotes,
        TotalComments,
        TotalLinks,
        TagsList,
        ROW_NUMBER() OVER (PARTITION BY PostTypeId ORDER BY Score DESC, ViewCount DESC, AnswerCount DESC) AS PostRank
    FROM
        PostMetrics
)
SELECT
    AU.UserId,
    AU.DisplayName,
    AU.Reputation,
    AU.Views,
    AU.UpVotes,
    AU.DownVotes,
    AU.TotalPosts,
    AU.TotalComments,
    AU.TotalVotes,
    AU.TotalBadges,
    AU.ActivityRank,
    TP.PostId,
    TP.PostTypeId,
    TP.CreationDate,
    TP.Score,
    TP.ViewCount,
    TP.AnswerCount,
    TP.CommentCount,
    TP.FavoriteCount,
    TP.OwnerUserId,
    TP.OwnerDisplayName,
    TP.AcceptedAnswerId,
    TP.LatestPostHistoryTypeId,
    TP.LatestPostHistoryDate,
    TP.LatestPostHistoryUserId,
    TP.TotalVotes,
    TP.TotalComments,
    TP.TotalLinks,
    TP.TagsList,
    TP.PostRank
FROM
    ActiveUsers AU
JOIN
    TopPosts TP ON AU.UserId = TP.OwnerUserId
WHERE
    AU.ActivityRank <= 100 AND
    TP.PostRank <= 10
ORDER BY
    AU.ActivityRank,
    TP.PostRank;

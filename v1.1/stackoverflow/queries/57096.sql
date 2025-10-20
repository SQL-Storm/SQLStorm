WITH UserActivity AS (
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(P.Id) AS TotalPosts,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COUNT(DISTINCT V.Id) AS TotalVotes,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        MAX(P.LastActivityDate) AS LastPostActivity,
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
        U.Id, U.Reputation, U.CreationDate
),
PostActivity AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.OwnerUserId,
        P.Tags,
        COUNT(V.Id) AS TotalVotesOnPost,
        COUNT(DISTINCT V.UserId) AS UniqueVoters,
        COUNT(C.Id) AS TotalCommentsOnPost,
        COUNT(DISTINCT PH.Id) AS TotalPostHistoryEntries,
        MAX(PH.CreationDate) AS LastPostHistoryDate,
        MAX(C.CreationDate) AS LastCommentOnPostDate,
        MAX(V.CreationDate) AS LastVoteOnPostDate
    FROM
        Posts P
    LEFT JOIN
        Votes V ON P.Id = V.PostId
    LEFT JOIN
        Comments C ON P.Id = C.PostId
    LEFT JOIN
        PostHistory PH ON P.Id = PH.PostId
    GROUP BY
        P.Id, P.PostTypeId, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount, P.CommentCount, P.FavoriteCount, P.OwnerUserId, P.Tags
),
TagActivity AS (
    SELECT
        T.Id AS TagId,
        T.TagName,
        T.Count AS TagCount,
        COUNT(P.Id) AS PostsWithTag,
        COUNT(DISTINCT V.UserId) AS UniqueVotersOnTagPosts,
        COUNT(DISTINCT C.UserId) AS UniqueCommentersOnTagPosts,
        COUNT(DISTINCT PH.UserId) AS UniqueEditorsOnTagPosts,
        MAX(P.CreationDate) AS LastPostWithTagDate,
        MAX(V.CreationDate) AS LastVoteOnTagPostDate,
        MAX(C.CreationDate) AS LastCommentOnTagPostDate,
        MAX(PH.CreationDate) AS LastEditOnTagPostDate
    FROM
        Tags T
    LEFT JOIN
        Posts P ON P.Tags LIKE '%' || '<' || T.TagName || '>' || '%'
    LEFT JOIN
        Votes V ON P.Id = V.PostId
    LEFT JOIN
        Comments C ON P.Id = C.PostId
    LEFT JOIN
        PostHistory PH ON P.Id = PH.PostId
    GROUP BY
        T.Id, T.TagName, T.Count
)
SELECT
    UA.UserId,
    UA.Reputation,
    UA.UserCreationDate,
    UA.TotalPosts,
    UA.TotalComments,
    UA.TotalVotes,
    UA.TotalBadges,
    PA.PostId,
    PA.PostTypeId,
    PA.PostCreationDate,
    PA.Score,
    PA.ViewCount,
    PA.AnswerCount,
    PA.CommentCount,
    PA.FavoriteCount,
    PA.TotalVotesOnPost,
    PA.UniqueVoters,
    PA.TotalCommentsOnPost,
    PA.TotalPostHistoryEntries,
    TA.TagId,
    TA.TagName,
    TA.TagCount,
    TA.PostsWithTag,
    TA.UniqueVotersOnTagPosts,
    TA.UniqueCommentersOnTagPosts,
    TA.UniqueEditorsOnTagPosts,
    UA.LastPostActivity,
    UA.LastCommentDate,
    UA.LastVoteDate,
    UA.LastBadgeDate,
    PA.LastPostHistoryDate,
    PA.LastCommentOnPostDate,
    PA.LastVoteOnPostDate,
    TA.LastPostWithTagDate,
    TA.LastVoteOnTagPostDate,
    TA.LastCommentOnTagPostDate,
    TA.LastEditOnTagPostDate
FROM
    UserActivity UA
JOIN
    PostActivity PA ON UA.UserId = PA.OwnerUserId
JOIN
    TagActivity TA ON PA.Tags LIKE '%' || '<' || TA.TagName || '>' || '%'
WHERE
    UA.TotalPosts > 10
    AND PA.ViewCount > 500
    AND TA.PostsWithTag > 20
ORDER BY
    UA.Reputation DESC,
    PA.Score DESC,
    TA.TagCount DESC
LIMIT 100;
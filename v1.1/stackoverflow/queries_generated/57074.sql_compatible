WITH UserActivity AS (
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COUNT(P.Id) AS TotalPosts,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COUNT(DISTINCT V.Id) AS TotalVotes,
        COUNT(DISTINCT B.Id) AS TotalBadges
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
        U.Id, U.Reputation, U.CreationDate, U.LastAccessDate
),
TopPosts AS (
  SELECT
      P.OwnerUserId,
      P.Id AS PostId,
      P.PostTypeId,
      P.CreationDate AS PostCreationDate,
      P.Score AS PostScore,
      P.ViewCount,
      P.AnswerCount,
      P.CommentCount,
      P.FavoriteCount,
      P.LastActivityDate,
      PT.Name AS PostTypeName,
      COUNT(V.Id) AS TotalVotesONPost,
      COUNT(DISTINCT C.Id) AS TotalCommentsOnPost,
      COUNT(DISTINCT PH.Id) AS TotalHistoryOnPost
  FROM
      Posts P
  JOIN
      PostTypes PT ON P.PostTypeId = PT.Id
  LEFT JOIN
      Votes V ON P.Id = V.PostId
  LEFT JOIN
      Comments C ON P.Id = C.PostId
  LEFT JOIN
      PostHistory PH ON P.Id = PH.PostId
  GROUP BY
      P.OwnerUserId, P.Id, P.PostTypeId, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount, P.CommentCount, P.FavoriteCount, P.LastActivityDate, PT.Name
),
Top100RecentPosts AS (
  SELECT
    *
  FROM
    TopPosts
  ORDER BY
    LastActivityDate DESC
  LIMIT 100
)
SELECT
    UA.UserId,
    UA.Reputation,
    UA.UserCreationDate,
    UA.LastAccessDate,
    UA.TotalPosts,
    UA.TotalComments,
    UA.TotalVotes,
    UA.TotalBadges,
    TP.PostId,
    TP.PostTypeId,
    TP.PostTypeName,
    TP.PostCreationDate,
    TP.PostScore,
    TP.ViewCount,
    TP.AnswerCount,
    COUNT(DISTINCT CASE WHEN V.VoteTypeId = 2 THEN V.Id END) AS TotalUpvotesOnPost,
    COUNT(DISTINCT CASE WHEN V.VoteTypeId = 3 THEN V.Id END) AS TotalDownvotesOnPost,
    TP.TotalVotesONPost,
    TP.TotalCommentsOnPost,
    TP.TotalHistoryOnPost
FROM
    UserActivity UA
JOIN
    Top100RecentPosts TP ON UA.UserId = TP.OwnerUserId
LEFT JOIN
    Votes V ON TP.PostId = V.PostId
GROUP BY
    UA.UserId,
    UA.Reputation,
    UA.UserCreationDate,
    UA.LastAccessDate,
    UA.TotalPosts,
    UA.TotalComments,
    UA.TotalVotes,
    UA.TotalBadges,
    TP.PostId,
    TP.PostTypeId,
    TP.PostCreationDate,
    TP.ViewCount,
    TP.AnswerCount,
    TP.PostTypeName,
    TP.PostScore,
    TP.TotalVotesONPost,
    TP.TotalCommentsOnPost,
    TP.TotalHistoryOnPost
ORDER BY
     TP.PostCreationDate DESC;
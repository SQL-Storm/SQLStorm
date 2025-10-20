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
HighReputationUsers AS (
    SELECT
        UserId,
        Reputation,
        UserCreationDate,
        LastAccessDate,
        TotalPosts,
        TotalComments,
        TotalVotes,
        TotalBadges,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS ReputationRank
    FROM
        UserActivity
)
SELECT
    H.UserId,
    H.Reputation,
    H.UserCreationDate,
    H.LastAccessDate,
    H.ReputationRank,
    H.TotalPosts,
    H.TotalComments,
    H.TotalVotes,
    H.TotalBadges,
    P.PostTypeId,
    P.CreationDate AS PostCreationDate,
    P.Score AS PostScore,
    P.ViewCount,
    P.AnswerCount,
    P.CommentCount,
    P.FavoriteCount,
    PH.PostHistoryTypeId,
    PH.CreationDate AS PostHistoryCreationDate,
    PH.Comment AS PostHistoryComment
FROM
    HighReputationUsers H
LEFT JOIN
    Posts P ON H.UserId = P.OwnerUserId
LEFT JOIN
    PostHistory PH ON P.Id = PH.PostId
WHERE
    H.ReputationRank <= 100
    AND P.CreationDate >= H.UserCreationDate
    AND P.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '1 year')
ORDER BY
    H.ReputationRank, P.Score DESC, P.ViewCount DESC
LIMIT 1000;
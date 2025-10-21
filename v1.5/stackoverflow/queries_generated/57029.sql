-- {"query": "57029.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2291, "output_tokens": 759} 

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
TopUsers AS (
    SELECT
        UserId,
        Reputation,
        UserCreationDate,
        LastAccessDate,
        TotalPosts,
        TotalComments,
        TotalVotes,
        TotalBadges,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, TotalPosts DESC, TotalComments DESC, TotalVotes DESC, TotalBadges DESC) AS Rank
    FROM
        UserActivity
)
SELECT
    TU.UserId,
    TU.Reputation,
    TU.UserCreationDate,
    TU.LastAccessDate,
    TU.TotalPosts,
    TU.TotalComments,
    TU.TotalVotes,
    TU.TotalBadges,
    TU.Rank,
    P.PostTypeId,
    P.CreationDate AS PostCreationDate,
    P.Score AS PostScore,
    P.ViewCount,
    P.AnswerCount,
    P.CommentCount,
    P.FavoriteCount,
    C.Score AS CommentScore,
    C.CreationDate AS CommentCreationDate,
    V.VoteTypeId,
    V.CreationDate AS VoteCreationDate,
    B.Name AS BadgeName,
    B.Date AS BadgeDate,
    B.Class AS BadgeClass,
    PT.Name AS PostTypeName,
    T.TagName,
    T.Count
FROM
    TopUsers TU
LEFT JOIN
    Posts P ON TU.UserId = P.OwnerUserId
LEFT JOIN
    Comments C ON TU.UserId = C.UserId
LEFT JOIN
    Votes V ON TU.UserId = V.UserId
LEFT JOIN
    Badges B ON TU.UserId = B.UserId
LEFT JOIN
    PostTypes PT ON P.PostTypeId = PT.Id
LEFT JOIN
    Tags T ON P.Id = T.ExcerptPostId OR P.Id = T.WikiPostId
WHERE
    TU.Rank <= 100
ORDER BY
    TU.Rank,
    P.CreationDate DESC,
    C.CreationDate DESC,
    V.CreationDate DESC,
    B.Date DESC;

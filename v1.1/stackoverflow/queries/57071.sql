WITH UserActivity AS (
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(P.Id) AS TotalPosts,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COUNT(DISTINCT V.Id) AS TotalVotes,
        MAX(P.LastActivityDate) AS LastPostActivity,
        MAX(C.CreationDate) AS LastCommentDate,
        MAX(V.CreationDate) AS LastVoteDate
    FROM
        Users U
    LEFT JOIN
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN
        Comments C ON U.Id = C.UserId
    LEFT JOIN
        Votes V ON U.Id = V.UserId
    GROUP BY
        U.Id, U.Reputation, U.CreationDate
),
HighReputationUsers AS (
    SELECT
        UserId,
        Reputation,
        UserCreationDate,
        TotalPosts,
        TotalComments,
        TotalVotes,
        LastPostActivity,
        LastCommentDate,
        LastVoteDate
    FROM
        UserActivity
    WHERE
        Reputation > 1000
),
ActiveUsers AS (
    SELECT
        UserId,
        Reputation,
        UserCreationDate,
        TotalPosts,
        TotalComments,
        TotalVotes,
        (TotalPosts + TotalComments + TotalVotes) AS Score,
        LastPostActivity,
        LastCommentDate,
        LastVoteDate
    FROM
        HighReputationUsers
    WHERE
        LastPostActivity > TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30 days'
        OR LastCommentDate > TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30 days'
        OR LastVoteDate > TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30 days'
    ORDER BY
        Score DESC
    LIMIT 100
),
TopTags AS (
    SELECT
        T.TagName,
        T.Count,
        P.Id AS PostId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        U.DisplayName AS OwnerDisplayName,
        U.Reputation AS OwnerReputation
    FROM
        Tags T
    JOIN
        Posts P ON T.ExcerptPostId = P.Id
    JOIN
        Users U ON P.OwnerUserId = U.Id
    WHERE
        T.Count > 500
    ORDER BY
        T.Count DESC,
        P.Score DESC
    LIMIT 50
)
SELECT
    AU.UserId,
    AU.Reputation,
    AU.UserCreationDate,
    AU.TotalPosts,
    AU.TotalComments,
    AU.TotalVotes,
    TT.TagName,
    TT.PostId,
    TT.PostTypeId,
    TT.PostCreationDate,
    TT.PostScore,
    TT.ViewCount,
    TT.AnswerCount,
    TT.OwnerDisplayName,
    TT.OwnerReputation
FROM
    ActiveUsers AU
JOIN
    TopTags TT ON AU.UserId = TT.OwnerReputation;
-- {"query": "57035.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2291, "output_tokens": 1114} 
WITH UserActivity AS (
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COUNT(P.Id) AS TotalPosts,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS TotalQuestions,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalAnswers,
        COALESCE(SUM(P.Score), 0) AS TotalScore,
        COUNT(C.Id) AS TotalComments,
        COUNT(V.Id) AS TotalVotes,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalUpvotes,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS TotalDownvotes
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
PostActivity AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.OwnerUserId,
        COUNT(V.Id) AS TotalVotesOnPost,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalUpvotesOnPost,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS TotalDownvotesOnPost,
        COUNT(C.Id) AS TotalCommentsOnPost,
        COUNT(DISTINCT PH.Id) AS TotalPostHistoryEntries
    FROM
        Posts P
    LEFT JOIN
        Votes V ON P.Id = V.PostId
    LEFT JOIN
        Comments C ON P.Id = C.PostId
    LEFT JOIN
        PostHistory PH ON P.Id = PH.PostId
    GROUP BY
        P.Id, P.PostTypeId, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount, P.CommentCount, P.OwnerUserId
),
TopUsers AS (
    SELECT
        UserId,
        Reputation,
        TotalPosts,
        TotalQuestions,
        TotalAnswers,
        TotalScore,
        TotalComments,
        TotalVotes,
        TotalBadges,
        TotalUpvotes,
        TotalDownvotes,
        ROW_NUMBER() OVER (ORDER BY TotalScore DESC, TotalPosts DESC, Reputation DESC) AS Rank
    FROM
        UserActivity
)
SELECT
    TU.UserId,
    TU.Reputation,
    TU.TotalPosts,
    TU.TotalQuestions,
    TU.TotalAnswers,
    TU.TotalScore,
    TU.TotalComments,
    TU.TotalVotes,
    TU.TotalBadges,
    TU.TotalUpvotes,
    TU.TotalDownvotes,
    TU.Rank,
    PA.PostId,
    PA.PostTypeId,
    PA.PostCreationDate,
    PA.Score AS PostScore,
    PA.ViewCount,
    PA.AnswerCount,
    PA.CommentCount,
    PA.TotalVotesOnPost,
    PA.TotalUpvotesOnPost,
    PA.TotalDownvotesOnPost,
    PA.TotalCommentsOnPost,
    PA.TotalPostHistoryEntries
FROM
    TopUsers TU
JOIN
    PostActivity PA ON TU.UserId = PA.OwnerUserId
WHERE
    TU.Rank <= 100
ORDER BY
    TU.Rank, PA.PostCreationDate DESC;
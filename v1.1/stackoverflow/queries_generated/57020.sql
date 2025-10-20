-- {"query": "57020.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2291, "output_tokens": 1072} 

WITH UserActivity AS (
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COUNT(P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        SUM(CASE WHEN P.PostTypeId = 1 THEN P.Score END) AS QuestionScore,
        SUM(CASE WHEN P.PostTypeId = 2 THEN P.Score END) AS AnswerScore,
        COUNT(C.Id) AS TotalComments,
        COUNT(V.Id) AS TotalVotes,
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
), TopUsers AS (
    SELECT
        UserId,
        Reputation,
        UserCreationDate,
        LastAccessDate,
        TotalPosts,
        TotalQuestions,
        TotalAnswers,
        QuestionScore,
        AnswerScore,
        TotalComments,
        TotalVotes,
        TotalBadges,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS ReputationRank
    FROM
        UserActivity
)
SELECT
    TU.UserId,
    TU.Reputation,
    TU.UserCreationDate,
    TU.LastAccessDate,
    TU.TotalPosts,
    TU.TotalQuestions,
    TU.TotalAnswers,
    TU.QuestionScore,
    TU.AnswerScore,
    TU.TotalComments,
    TU.TotalVotes,
    TU.TotalBadges,
    TU.ReputationRank,
    P.Id AS LastPostId,
    P.PostTypeId,
    P.CreationDate AS LastPostDate,
    P.Score AS LastPostScore,
    P.ViewCount AS LastPostViewCount,
    P.Title AS LastPostTitle,
    P.Tags AS LastPostTags,
    C.Id AS LastCommentId,
    C.PostId AS LastCommentPostId,
    C.CreationDate AS LastCommentDate,
    C.Score AS LastCommentScore,
    C.Text AS LastCommentText,
    V.Id AS LastVoteId,
    V.PostId AS LastVotePostId,
    V.VoteTypeId,
    V.CreationDate AS LastVoteDate,
    B.Id AS LastBadgeId,
    B.Name AS LastBadgeName,
    B.Date AS LastBadgeDate,
    B.Class AS LastBadgeClass,
    B.TagBased AS LastBadgeTagBased
FROM
    TopUsers TU
LEFT JOIN
    Posts P ON TU.UserId = P.OwnerUserId AND P.CreationDate = (
        SELECT MAX(P2.CreationDate)
        FROM Posts P2
        WHERE P2.OwnerUserId = TU.UserId
    )
LEFT JOIN
    Comments C ON TU.UserId = C.UserId AND C.CreationDate = (
        SELECT MAX(C2.CreationDate)
        FROM Comments C2
        WHERE C2.UserId = TU.UserId
    )
LEFT JOIN
    Votes V ON TU.UserId = V.UserId AND V.CreationDate = (
        SELECT MAX(V2.CreationDate)
        FROM Votes V2
        WHERE V2.UserId = TU.UserId
    )
LEFT JOIN
    Badges B ON TU.UserId = B.UserId AND B.Date = (
        SELECT MAX(B2.Date)
        FROM Badges B2
        WHERE B2.UserId = TU.UserId
    )
WHERE
    TU.ReputationRank <= 100
ORDER BY
    TU.ReputationRank, TU.UserId;

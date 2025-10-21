-- {"query": "57100.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2291, "output_tokens": 1044} 

WITH UserActivity AS (
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COUNT(P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        SUM(CASE WHEN P.PostTypeId = 1 THEN P.Score ELSE 0 END) AS QuestionScore,
        SUM(CASE WHEN P.PostTypeId = 2 THEN P.Score ELSE 0 END) AS AnswerScore,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COUNT(DISTINCT V.Id) AS TotalVotes,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
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
    WHERE
        U.CreationDate >= DATEADD(YEAR, -1, GETDATE())
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
        TotalUpVotes,
        TotalDownVotes,
        TotalBadges,
        GoldBadges,
        SilverBadges,
        BronzeBadges,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, TotalPosts DESC) AS Rank
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
    TU.TotalUpVotes,
    TU.TotalDownVotes,
    TU.TotalBadges,
    TU.GoldBadges,
    TU.SilverBadges,
    TU.BronzeBadges,
    TU.Rank,
    P.Title,
    P.Body,
    P.CreationDate AS PostCreationDate,
    P.Score AS PostScore,
    P.ViewCount,
    P.AnswerCount,
    P.CommentCount,
    P.LastActivityDate,
    T.TagName,
    V.VoteTypeId,
    V.CreationDate AS VoteCreationDate
FROM
    TopUsers TU
LEFT JOIN
    Posts P ON TU.UserId = P.OwnerUserId
LEFT JOIN
    Tags T ON P.Id = T.ExcerptPostId OR P.Id = T.WikiPostId
LEFT JOIN
    Votes V ON P.Id = V.PostId
WHERE
    TU.Rank <= 100
ORDER BY
    TU.Rank, P.CreationDate DESC;

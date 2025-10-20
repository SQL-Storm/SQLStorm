-- {"query": "57082.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2291, "output_tokens": 1102} 

WITH UserActivity AS (
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(P.Id) AS TotalPosts,
        COUNT(DISTINCT P.Id) AS UniquePosts,
        MAX(P.CreationDate) AS LastPostDate,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 1 THEN P.Score END), 0) AS TotalQuestionScore,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 2 THEN P.Score END), 0) AS TotalAnswerScore,
        SUM(P.ViewCount) AS TotalViewCount,
        COUNT(DISTINCT V.Id) AS TotalVotes,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS TotalGoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS TotalSilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS TotalBronzeBadges,
        COUNT(DISTINCT PH.Id) AS TotalPostHistory,
        COUNT(DISTINCT PL.Id) AS TotalPostLinks
    FROM
        Users U
    LEFT JOIN
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN
        Votes V ON P.Id = V.PostId AND V.UserId = U.Id
    LEFT JOIN
        Comments C ON P.Id = C.PostId AND C.UserId = U.Id
    LEFT JOIN
        Badges B ON U.Id = B.UserId
    LEFT JOIN
        PostHistory PH ON P.Id = PH.PostId AND PH.UserId = U.Id
    LEFT JOIN
        PostLinks PL ON P.Id = PL.PostId
    WHERE
        U.CreationDate BETWEEN '2023-01-01' AND '2023-12-31'
    GROUP BY
        U.Id, U.Reputation, U.CreationDate
),
TopUsers AS (
    SELECT
        UserId,
        Reputation,
        UserCreationDate,
        TotalPosts,
        UniquePosts,
        LastPostDate,
        TotalQuestions,
        TotalAnswers,
        TotalQuestionScore,
        TotalAnswerScore,
        TotalViewCount,
        TotalVotes,
        TotalUpVotes,
        TotalDownVotes,
        TotalComments,
        TotalBadges,
        TotalGoldBadges,
        TotalSilverBadges,
        TotalBronzeBadges,
        TotalPostHistory,
        TotalPostLinks,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, TotalPosts DESC, TotalVotes DESC) AS Rank
    FROM
        UserActivity
)
SELECT
    T.UserId,
    T.Reputation,
    T.UserCreationDate,
    T.Rank,
    T.TotalPosts,
    T.UniquePosts,
    T.LastPostDate,
    T.TotalQuestions,
    T.TotalAnswers,
    T.TotalQuestionScore,
    T.TotalAnswerScore,
    T.TotalViewCount,
    T.TotalVotes,
    T.TotalUpVotes,
    T.TotalDownVotes,
    T.TotalComments,
    T.TotalBadges,
    T.TotalGoldBadges,
    T.TotalSilverBadges,
    T.TotalBronzeBadges,
    T.TotalPostHistory,
    T.TotalPostLinks
FROM
    TopUsers T
WHERE
    T.Rank <= 100
ORDER BY
    T.Rank;

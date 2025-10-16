WITH UserActivity AS (
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(COALESCE(P.Score,0)) AS TotalScore,
        MAX(P.CreationDate) AS LastPostDate,
        COUNT(C.Id) AS TotalComments,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotesGiven,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotesGiven
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
TagMetrics AS (
    SELECT
        T.Id AS TagId,
        T.TagName,
        P.Id AS PostId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        DENSE_RANK() OVER (PARTITION BY T.Id ORDER BY P.CreationDate DESC) AS Rank
    FROM
        Tags T
    LEFT JOIN
        Posts P ON T.ExcerptPostId = P.Id OR T.WikiPostId = P.Id
    WHERE
        T.Count > 1000
)
SELECT
    UA.UserId,
    UA.Reputation,
    UA.UserCreationDate,
    UA.TotalPosts,
    UA.TotalQuestions,
    UA.TotalAnswers,
    UA.TotalScore,
    UA.LastPostDate,
    UA.TotalComments,
    UA.TotalUpVotesGiven,
    UA.TotalDownVotesGiven,
    TM.TagId,
    TM.TagName,
    TM.PostId,
    TM.PostCreationDate,
    TM.PostScore,
    TM.ViewCount,
    TM.AnswerCount,
    TM.CommentCount,
    TM.Rank,
    CASE
        WHEN UA.TotalPosts > 100 THEN 'Active'
        WHEN UA.TotalPosts BETWEEN 50 AND 100 THEN 'Moderately Active'
        ELSE 'Inactive'
    END AS ActivityLevel,
    CASE
        WHEN UA.TotalUpVotesGiven > UA.TotalDownVotesGiven THEN 'Positive Voter'
        WHEN UA.TotalUpVotesGiven < UA.TotalDownVotesGiven THEN 'Negative Voter'
        ELSE 'Neutral Voter'
    END AS VotingTendency
FROM
    UserActivity UA
LEFT JOIN
    TagMetrics TM ON UA.UserId = (
        SELECT
            OwnerUserId
        FROM
            Posts
        WHERE
            Id = TM.PostId
            AND PostTypeId = 1
        LIMIT 1
    )
WHERE
    (UA.TotalPosts > 50 OR UA.TotalComments > 100)
    AND TM.Rank <= 10
GROUP BY
    UA.UserId,
    UA.Reputation,
    UA.UserCreationDate,
    UA.TotalPosts,
    UA.TotalQuestions,
    UA.TotalAnswers,
    UA.TotalScore,
    UA.LastPostDate,
    UA.TotalComments,
    UA.TotalUpVotesGiven,
    UA.TotalDownVotesGiven,
    TM.TagId,
    TM.TagName,
    TM.PostId,
    TM.PostCreationDate,
    TM.PostScore,
    TM.ViewCount,
    TM.AnswerCount,
    TM.CommentCount,
    TM.Rank
ORDER BY
    UA.Reputation DESC, TM.Rank
LIMIT 100;
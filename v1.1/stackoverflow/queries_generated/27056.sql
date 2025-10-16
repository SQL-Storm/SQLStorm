-- {"query": "27056.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2337, "output_tokens": 1646} 

WITH UserActivity AS (
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.DisplayName,
        U.LastAccessDate,
        U.Views,
        U.UpVotes,
        U.DownVotes,
        COUNT(P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(P.Score) AS TotalScore,
        MAX(P.CreationDate) AS LastPostDate,
        LAG(U.Reputation, 1) OVER (ORDER BY U.Reputation DESC) AS PreviousReputation,
        LEAD(U.Reputation, 1) OVER (ORDER BY U.Reputation DESC) AS NextReputation
    FROM
        Users U
    LEFT JOIN
        Posts P ON U.Id = P.OwnerUserId
    GROUP BY
        U.Id, U.Reputation, U.CreationDate, U.DisplayName, U.LastAccessDate,
        U.Views, U.UpVotes, U.DownVotes
),
PostActivity AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.Score,
        P.ViewCount,
        P.OwnerUserId,
        P.LastActivityDate,
        P.Title,
        P.Tags,
        P.AnswerCount,
        COALESCE(A.Id, -1) AS AcceptedAnswerId,
        COUNT(C.Id) AS TotalComments,
        COUNT(V.Id) FILTER (WHERE V.VoteTypeId = 2) AS TotalUpVotes,
        COUNT(V.Id) FILTER (WHERE V.VoteTypeId = 3) AS TotalDownVotes,
        COUNT(DISTINCT V.UserId) AS UniqueVoters,
        (CASE
            WHEN P.PostTypeId = 1 AND P.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN P.PostTypeId = 1 AND P.CommunityOwnedDate IS NOT NULL THEN 'Community Wiki'
            ELSE 'Open'
        END) AS PostStatus,
        LAG(P.Score, 1) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS PreviousPostScore,
        LEAD(P.Score, 1) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS NextPostScore
    FROM
        Posts P
    LEFT JOIN
        Posts A ON P.AcceptedAnswerId = A.Id
    LEFT JOIN
        Comments C ON P.Id = C.PostId
    LEFT JOIN
        Votes V ON P.Id = V.PostId
    GROUP BY
        P.Id, P.PostTypeId, P.CreationDate, P.Score, P.ViewCount, P.OwnerUserId,
        P.LastActivityDate, P.Title, P.Tags, P.AnswerCount, A.Id
),
ActiveUsers AS (
    SELECT
        UserId,
        Reputation,
        TotalPosts,
        TotalQuestions,
        TotalAnswers,
        TotalScore,
        UserCreationDate,
        LastPostDate,
        DENSE_RANK() OVER (ORDER BY TotalScore DESC) AS ScoreRank,
        DENSE_RANK() OVER (ORDER BY TotalPosts DESC) AS PostRank,
        DENSE_RANK() OVER (ORDER BY Reputation DESC) AS ReputationRank,
        NTILE(100) OVER (ORDER BY Reputation DESC) AS ReputationPercentile,
        LAG(TotalScore, 1) OVER (ORDER BY TotalScore DESC) AS PreviousTotalScore,
        LEAD(TotalScore, 1) OVER (ORDER BY TotalScore DESC) AS NextTotalScore
    FROM
        UserActivity
    WHERE
        LastAccessDate > NOW() - INTERVAL '30 days'
)
SELECT
    AU.UserId,
    AU.DisplayName,
    AU.Reputation,
    AU.TotalPosts,
    AU.TotalQuestions,
    AU.TotalAnswers,
    AU.TotalScore,
    AU.ScoreRank,
    AU.PostRank,
    AU.ReputationRank,
    AU.ReputationPercentile,
    PA.PostId,
    PA.PostTypeId,
    PA.Title,
    PA.Tags,
    PA.Score,
    PA.ViewCount,
    PA.AnswerCount,
    PA.TotalComments,
    PA.TotalUpVotes,
    PA.TotalDownVotes,
    PA.UniqueVoters,
    PA.PostStatus,
    PA.PreviousPostScore,
    PA.NextPostScore,
    PA.PostCreationDate,
    EXTRACT(EPOCH FROM (AU.LastPostDate - AU.UserCreationDate)) / 86400 AS DaysSinceFirstPost,
    CASE
        WHEN PA.PostStatus = 'Closed' THEN 'Closed Question'
        WHEN PA.PostStatus = 'Community Wiki' THEN 'Community Wiki Post'
        ELSE 'Open Post'
    END AS PostCategory,
    (SELECT COUNT(*)
     FROM Badges B
     WHERE B.UserId = AU.UserId AND B.Class = 1) AS GoldBadges,
    (SELECT COUNT(*)
     FROM Badges B
     WHERE B.UserId = AU.UserId AND B.Class = 2) AS SilverBadges,
    (SELECT COUNT(*)
     FROM Badges B
     WHERE B.UserId = AU.UserId AND B.Class = 3) AS BronzeBadges,
    (SELECT COUNT(PH.Id)
     FROM PostHistory PH
     WHERE PH.PostId = PA.PostId AND PH.UserId = AU.UserId) AS UserPostEdits,
    (SELECT STRING_AGG(T.TagName, ', ')
     FROM Tags T
     WHERE PA.Tags LIKE ('%<' || T.TagName || '>%')) AS ParsedTags
FROM
    ActiveUsers AU
JOIN
    PostActivity PA ON AU.UserId = PA.OwnerUserId
WHERE
    AU.TotalPosts > 10 AND
    PA.ViewCount > 500 AND
    (PA.TotalUpVotes > 0 OR PA.TotalDownVotes > 0)
ORDER BY
    AU.Reputation DESC, PA.Score DESC;

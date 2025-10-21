-- {"query": "35067.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 620} 
WITH TopUsers AS (
    SELECT U.Id AS UserId, U.DisplayName, U.Reputation, COUNT(P.Id) AS TotalPosts
    FROM Users U
    JOIN Posts P ON U.Id = P.OwnerUserId
    WHERE P.CreationDate >= NOW() - INTERVAL '1 year'
    GROUP BY U.Id, U.DisplayName, U.Reputation
    HAVING COUNT(P.Id) > 10
    ORDER BY U.Reputation DESC
    LIMIT 50
),
UserActivity AS (
    SELECT
        TU.UserId,
        COUNT(DISTINCT PQ.Id) AS QuestionsAsked,
        COUNT(DISTINCT PA.Id) AS AnswersGiven,
        COALESCE(SUM(PC.Score), 0) AS TotalCommentScore,
        COALESCE(SUM(P.Score), 0) AS TotalPostScore
    FROM TopUsers TU
    LEFT JOIN Posts PQ ON TU.UserId = PQ.OwnerUserId AND PQ.PostTypeId = 1
    LEFT JOIN Posts PA ON TU.UserId = PA.OwnerUserId AND PA.PostTypeId = 2
    LEFT JOIN Comments PC ON TU.UserId = PC.UserId
    LEFT JOIN Posts P ON TU.UserId = P.OwnerUserId
    GROUP BY TU.UserId
),
UserBadges AS (
    SELECT
        B.UserId,
        COUNT(*) FILTER(WHERE B.Class = 1) AS GoldBadges,
        COUNT(*) FILTER(WHERE B.Class = 2) AS SilverBadges,
        COUNT(*) FILTER(WHERE B.Class = 3) AS BronzeBadges
    FROM Badges B
    WHERE B.Date >= NOW() - INTERVAL '1 year'
    GROUP BY B.UserId
),
UserVoteStats AS (
    SELECT
        U.Id AS UserId,
        COUNT(*) FILTER(WHERE V.VoteTypeId = 2) AS UpvotesReceived,
        COUNT(*) FILTER(WHERE V.VoteTypeId = 3) AS DownvotesReceived,
        COUNT(*) FILTER(WHERE V.VoteTypeId = 5) AS FavoritesReceived
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Votes V ON P.Id = V.PostId
    GROUP BY U.Id
)
SELECT
    TU.UserId,
    TU.DisplayName,
    TU.Reputation,
    TU.TotalPosts,
    UA.QuestionsAsked,
    UA.AnswersGiven,
    UA.TotalCommentScore,
    UA.TotalPostScore,
    UB.GoldBadges,
    UB.SilverBadges,
    UB.BronzeBadges,
    UVS.UpvotesReceived,
    UVS.DownvotesReceived,
    UVS.FavoritesReceived
FROM TopUsers TU
LEFT JOIN UserActivity UA ON TU.UserId = UA.UserId
LEFT JOIN UserBadges UB ON TU.UserId = UB.UserId
LEFT JOIN UserVoteStats UVS ON TU.UserId = UVS.UserId
ORDER BY TU.Reputation DESC, TU.UserId
;
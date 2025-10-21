-- {"query": "58036.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 1324} 

WITH ActiveUsers AS (
    SELECT 
        U.Id, 
        U.DisplayName, 
        U.Reputation,
        COUNT(DISTINCT B.Id) AS GoldBadges,
        COUNT(DISTINCT P.Id) FILTER (WHERE P.PostTypeId = 1) AS QuestionsAsked,
        COUNT(DISTINCT P2.Id) FILTER (WHERE P.PostTypeId = 2) AS AnswersProvided,
        SUM(P.Score) AS TotalPostScore
    FROM Users U
    LEFT JOIN Badges B ON U.Id = B.UserId AND B.Class = 1
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Posts P2 ON U.Id = P2.OwnerUserId
    WHERE U.Reputation > 10000
      AND P.CreationDate >= NOW() - INTERVAL '1 YEAR'
    GROUP BY U.Id
), PostStats AS (
    SELECT 
        P.OwnerUserId,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COUNT(DISTINCT V.Id) FILTER (WHERE V.VoteTypeId = 2) AS Upvotes,
        COUNT(DISTINCT V.Id) FILTER (WHERE V.VoteTypeId = 3) AS Downvotes,
        COUNT(DISTINCT PH.Id) FILTER (WHERE PH.PostHistoryTypeId IN (5,6)) AS EditsMade
    FROM Posts P
    LEFT JOIN Comments C ON P.Id = C.PostId
    LEFT JOIN Votes V ON P.Id = V.PostId
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    GROUP BY P.OwnerUserId
)
SELECT 
    AU.*,
    PS.TotalComments,
    PS.Upvotes,
    PS.Downvotes,
    PS.EditsMade,
    RANK() OVER (ORDER BY AU.TotalPostScore DESC) AS PostScoreRank,
    ARRAY_AGG(DISTINCT SPLIT_PART(P.Tags, '><', 1)) AS TopTags
FROM ActiveUsers AU
JOIN PostStats PS ON AU.Id = PS.OwnerUserId
LEFT JOIN Posts P ON AU.Id = P.OwnerUserId AND P.PostTypeId = 1
WHERE AU.QuestionsAsked > 50
  AND PS.EditsMade > 20
GROUP BY 
    AU.Id, 
    AU.DisplayName, 
    AU.Reputation, 
    AU.GoldBadges, 
    AU.QuestionsAsked, 
    AU.AnswersProvided, 
    AU.TotalPostScore, 
    PS.TotalComments, 
    PS.Upvotes, 
    PS.Downvotes, 
    PS.EditsMade
ORDER BY 
    AU.Reputation DESC, 
    PS.Upvotes DESC, 
    PS.EditsMade DESC
LIMIT 100;

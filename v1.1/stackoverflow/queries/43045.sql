WITH TopUsers AS (
    SELECT 
        U.Id,
        U.DisplayName,
        U.Reputation,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        RANK() OVER (ORDER BY U.Reputation DESC) AS UserRank
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    WHERE P.CreationDate BETWEEN (DATE '2024-10-01' - INTERVAL '1' YEAR) AND DATE '2024-10-01'
    GROUP BY U.Id, U.DisplayName, U.Reputation
    HAVING COUNT(DISTINCT P.Id) > 10
),
PostActivity AS (
    SELECT 
        P.Id AS PostId,
        P.Title,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        (SELECT COUNT(*) FROM Comments C WHERE C.PostId = P.Id) AS TotalComments,
        (SELECT COUNT(*) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 2) AS UpVotes,
        (SELECT COUNT(*) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 3) AS DownVotes
    FROM Posts P
    WHERE P.PostTypeId = 1
      AND P.CreationDate BETWEEN (DATE '2024-10-01' - INTERVAL '1' YEAR) AND DATE '2024-10-01'
)
SELECT 
    TU.DisplayName,
    TU.Reputation,
    TU.TotalQuestions,
    TU.TotalAnswers,
    TU.TotalBadges,
    PA.Title,
    PA.Score,
    PA.ViewCount,
    PA.AnswerCount,
    PA.CommentCount,
    PA.TotalComments,
    PA.UpVotes,
    PA.DownVotes
FROM TopUsers TU
JOIN Posts P ON TU.Id = P.OwnerUserId
JOIN PostActivity PA ON P.Id = PA.PostId
WHERE TU.UserRank <= 10
GROUP BY
    TU.DisplayName,
    TU.Reputation,
    TU.TotalQuestions,
    TU.TotalAnswers,
    TU.TotalBadges,
    PA.Title,
    PA.Score,
    PA.ViewCount,
    PA.AnswerCount,
    PA.CommentCount,
    PA.TotalComments,
    PA.UpVotes,
    PA.DownVotes,
    TU.UserRank,
    TU.Id,
    PA.PostId
ORDER BY TU.Reputation DESC, PA.Score DESC
LIMIT 100;
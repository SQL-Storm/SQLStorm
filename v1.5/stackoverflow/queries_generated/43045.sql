-- {"query": "43045.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 530} 

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
    WHERE P.CreationDate BETWEEN CURRENT_DATE - INTERVAL '1 YEAR' AND CURRENT_DATE
    GROUP BY U.Id
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
        (SELECT COUNT(*) FROM Comments WHERE PostId = P.Id) AS TotalComments,
        (SELECT COUNT(*) FROM Votes WHERE PostId = P.Id AND VoteTypeId = 2) AS UpVotes,
        (SELECT COUNT(*) FROM Votes WHERE PostId = P.Id AND VoteTypeId = 3) AS DownVotes
    FROM Posts P
    WHERE P.PostTypeId = 1
    AND P.CreationDate BETWEEN CURRENT_DATE - INTERVAL '1 YEAR' AND CURRENT_DATE
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
ORDER BY TU.Reputation DESC, PA.Score DESC
LIMIT 100;


WITH UserReputation AS (
    SELECT 
        U.Id AS UserId,
        U.Reputation,
        U.DisplayName,
        COUNT(DISTINCT P.Id) AS QuestionCount,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId AND P.PostTypeId = 1
    LEFT JOIN 
        Votes V ON P.Id = V.PostId
    WHERE 
        U.Reputation > 1000
    GROUP BY 
        U.Id, U.Reputation, U.DisplayName
),

TopQuestions AS (
    SELECT 
        P.Id AS PostId,
        P.Title,
        P.CreationDate,
        P.Score,
        @row_number := IF(@prev_score = P.Score, @row_number + 1, 1) AS ScoreRank,
        @prev_score := P.Score
    FROM 
        Posts P, (SELECT @row_number := 0, @prev_score := NULL) AS init
    WHERE 
        P.PostTypeId = 1 AND P.AcceptedAnswerId IS NOT NULL
    ORDER BY 
        P.Score DESC
)

SELECT 
    UR.DisplayName,
    UR.Reputation,
    UR.QuestionCount,
    UR.Upvotes,
    UR.Downvotes,
    TQ.Title,
    TQ.Score,
    TQ.CreationDate
FROM 
    UserReputation UR
LEFT JOIN 
    TopQuestions TQ ON UR.QuestionCount > 10 AND UR.Upvotes > UR.Downvotes
WHERE 
    TQ.ScoreRank <= 10
ORDER BY 
    UR.Reputation DESC, 
    TQ.Score DESC 
LIMIT 20;

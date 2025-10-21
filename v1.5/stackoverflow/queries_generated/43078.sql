-- {"query": "43078.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 476} 

WITH TopUsers AS (
    SELECT 
        U.Id, 
        U.DisplayName, 
        U.Reputation, 
        COUNT(DISTINCT B.Id) AS BadgeCount,
        COUNT(DISTINCT P.Id) AS PostCount
    FROM 
        Users U
    LEFT JOIN 
        Badges B ON U.Id = B.UserId
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    WHERE 
        U.Reputation > 1000
    GROUP BY 
        U.Id, U.DisplayName, U.Reputation
    ORDER BY 
        U.Reputation DESC
    LIMIT 100
),
UserActivity AS (
    SELECT 
        TU.Id,
        COUNT(DISTINCT PH.Id) AS EditCount,
        COUNT(DISTINCT PH.CreationDate) AS ActivityDates
    FROM 
        TopUsers TU
    JOIN 
        PostHistory PH ON TU.Id = PH.UserId
    WHERE 
        PH.PostHistoryTypeId IN (4, 5, 6)
    GROUP BY 
        TU.Id
)
SELECT 
    TU.Id, 
    TU.DisplayName, 
    TU.Reputation, 
    TU.BadgeCount, 
    TU.PostCount,
    UA.EditCount,
    SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
    SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
    AVG(P.Score) AS AvgPostScore
FROM 
    TopUsers TU
LEFT JOIN 
    UserActivity UA ON TU.Id = UA.Id
LEFT JOIN 
    Posts P ON TU.Id = P.OwnerUserId
GROUP BY 
    TU.Id, TU.DisplayName, TU.Reputation, TU.BadgeCount, TU.PostCount, UA.EditCount
ORDER BY 
    TU.Reputation DESC, UA.EditCount DESC;

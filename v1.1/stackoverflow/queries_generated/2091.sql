-- {"query": "2091.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 476} 

WITH TopUsers AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        ROW_NUMBER() OVER (ORDER BY U.Reputation DESC) AS Rank
    FROM Users U
    WHERE U.Reputation > 1000
),
TopAnswerers AS (
    SELECT
        A.OwnerUserId,
        COUNT(*) AS AnswerCount
    FROM Posts A
    WHERE A.PostTypeId = 2
    GROUP BY A.OwnerUserId
    HAVING COUNT(*) > 50
),
QuestionActivity AS (
    SELECT
        Q.Id AS QuestionId,
        Q.Title,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 WHEN V.VoteTypeId = 3 THEN -1 ELSE 0 END), 0) AS NetVotes,
        COUNT(DISTINCT C.Id) AS CommentCount
    FROM Posts Q
    LEFT JOIN Votes V ON V.PostId = Q.Id
    LEFT JOIN Comments C ON C.PostId = Q.Id
    WHERE Q.PostTypeId = 1
    GROUP BY Q.Id, Q.Title
),
BadgeStatistics AS (
    SELECT
        B.UserId,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges B
    GROUP BY B.UserId
)
SELECT
    TU.UserId,
    TU.DisplayName,
    TU.Reputation,
    TA.AnswerCount,
    BS.GoldBadges,
    BS.SilverBadges,
    BS.BronzeBadges,
    CONCAT(
        'User: ', TU.DisplayName, 
        CASE 
            WHEN BS.GoldBadges > 5 THEN ' - Star Contributor' 
            ELSE '' 
        END
    ) AS UserDescription
FROM TopUsers TU
LEFT JOIN TopAnswerers TA ON TU.UserId = TA.OwnerUserId
LEFT JOIN BadgeStatistics BS ON TU.UserId = BS.UserId
WHERE TU.Rank <= 50
ORDER BY TU.Rank ASC;

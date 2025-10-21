-- {"query": "2068.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 498} 

WITH ActiveUsers AS (
    SELECT 
        U.Id AS UserId, 
        U.DisplayName, 
        U.Reputation, 
        COUNT(P.Id) AS PostCount
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    WHERE U.LastAccessDate > CURRENT_TIMESTAMP - INTERVAL '1 year'
    GROUP BY U.Id, U.DisplayName, U.Reputation
),
HighRepActiveUsers AS (
    SELECT 
        UserId, 
        DisplayName, 
        Reputation, 
        PostCount 
    FROM ActiveUsers 
    WHERE Reputation > 1000
),
BadgeCounts AS (
    SELECT 
        UserId, 
        COUNT(*) AS BadgeCount 
    FROM Badges 
    WHERE Class = 1
    GROUP BY UserId
),
PostEngagement AS (
    SELECT
        P.Id AS PostId,
        P.Title,
        COALESCE(MIN(PC.Score), 0) AS MinCommentScore,
        SUM(PC.Score) AS TotalCommentScore,
        AVG(PC.Score) AS AvgCommentScore
    FROM Posts P
    LEFT JOIN Comments PC ON P.Id = PC.PostId
    WHERE P.PostTypeId IN (1, 2)
    GROUP BY P.Id, P.Title
)
SELECT 
    HU.UserId, 
    HU.DisplayName, 
    HU.Reputation, 
    HU.PostCount, 
    COALESCE(BC.BadgeCount, 0) AS GoldBadgeCount,
    PE.PostId,
    PE.Title,
    PE.MinCommentScore,
    PE.TotalCommentScore,
    PE.AvgCommentScore
FROM HighRepActiveUsers HU
LEFT JOIN BadgeCounts BC ON HU.UserId = BC.UserId
LEFT JOIN (
    SELECT
        P.OwnerUserId,
        MAX(PE.AvgCommentScore) AS MaxAvgCommentScore
    FROM PostEngagement PE
    JOIN Posts P ON PE.PostId = P.Id
    WHERE P.OwnerUserId IS NOT NULL
    GROUP BY P.OwnerUserId
) AS MaxEngagement ON HU.UserId = MaxEngagement.OwnerUserId
JOIN PostEngagement PE ON MaxEngagement.MaxAvgCommentScore = PE.AvgCommentScore
WHERE COALESCE(PE.PostId, 0) > 0
ORDER BY HU.Reputation DESC, PE.TotalCommentScore DESC, HU.UserId ASC;

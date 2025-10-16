-- {"query": "1071.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 440} 
WITH UserReputation AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate,
        ROW_NUMBER() OVER (ORDER BY U.Reputation DESC) AS ReputationRank
    FROM 
        Users U
), 
UserBadges AS (
    SELECT 
        B.UserId,
        COUNT(CASE WHEN B.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN B.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN B.Class = 3 THEN 1 END) AS BronzeBadges
    FROM 
        Badges B
    GROUP BY 
        B.UserId
), 
PostStats AS (
    SELECT 
        P.OwnerUserId,
        COUNT(P.Id) AS TotalPosts,
        SUM(P.Score) AS TotalScore,
        MAX(P.CreationDate) AS LastPostDate
    FROM 
        Posts P
    WHERE 
        P.CreationDate >= cast('2024-10-01' as date) - INTERVAL '1 year'
    GROUP BY 
        P.OwnerUserId
)

SELECT 
    UR.DisplayName,
    UR.Reputation,
    UB.GoldBadges,
    UB.SilverBadges,
    UB.BronzeBadges,
    PS.TotalPosts,
    PS.TotalScore,
    (SELECT COUNT(*) 
     FROM Votes V 
     WHERE V.UserId = UR.UserId AND V.CreationDate >= cast('2024-10-01' as date) - INTERVAL '1 month') AS RecentVotes,
    (SELECT STRING_AGG(P.Title, ', ') 
     FROM Posts P 
     WHERE P.OwnerUserId = UR.UserId 
     AND P.CreationDate BETWEEN cast('2024-10-01' as date) - INTERVAL '1 month' AND cast('2024-10-01' as date)) AS RecentPostTitles
FROM 
    UserReputation UR
LEFT JOIN 
    UserBadges UB ON UR.UserId = UB.UserId
LEFT JOIN 
    PostStats PS ON UR.UserId = PS.OwnerUserId
WHERE 
    UR.Reputation > 1000
ORDER BY 
    UR.Reputation DESC
LIMIT 10;
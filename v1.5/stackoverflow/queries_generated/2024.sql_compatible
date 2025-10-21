WITH UserStats AS (
    SELECT 
        U.Id AS UserId, 
        U.DisplayName, 
        U.Reputation, 
        COALESCE(SUM(CASE WHEN B1.Class = 1 THEN 1 ELSE 0 END), 0) AS GoldBadges, 
        COALESCE(SUM(CASE WHEN B1.Class = 2 THEN 1 ELSE 0 END), 0) AS SilverBadges, 
        COALESCE(SUM(CASE WHEN B1.Class = 3 THEN 1 ELSE 0 END), 0) AS BronzeBadges
    FROM 
        Users U
    LEFT JOIN 
        Badges B1 ON U.Id = B1.UserId
    WHERE 
        U.Reputation > 1000
    GROUP BY 
        U.Id, U.DisplayName, U.Reputation
),
TopQuestions AS (
    SELECT 
        P.Id, 
        P.Title, 
        P.OwnerUserId, 
        P.Score,
        B2.Class AS TopBadgeClass
    FROM 
        Posts P
    LEFT JOIN 
        Badges B2 ON P.OwnerUserId = B2.UserId
    WHERE 
        P.PostTypeId = 1 AND P.Score > 100
    ORDER BY 
        P.Score DESC
    LIMIT 10
)
SELECT 
    US.UserId, 
    US.DisplayName, 
    US.Reputation, 
    US.GoldBadges, 
    US.SilverBadges, 
    US.BronzeBadges, 
    TQ.Title AS TopQuestionTitle, 
    TQ.Score AS TopQuestionScore, 
    COALESCE(TQ.TopBadgeClass, -1) AS TopBadgeClass
FROM 
    UserStats US
LEFT JOIN 
    TopQuestions TQ ON US.UserId = TQ.OwnerUserId
WHERE 
    COALESCE(TQ.Score, 0) > 200
    AND (
        US.GoldBadges > 5 OR 
        US.SilverBadges > 10 OR 
        US.BronzeBadges > 20
    )
ORDER BY 
    US.Reputation DESC, TQ.Score DESC;
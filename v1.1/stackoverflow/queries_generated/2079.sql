-- {"query": "2079.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 636} 

WITH BadgeStats AS (
    SELECT 
        UserId,
        COUNT(*) AS TotalBadges,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges
    FROM 
        Badges
    GROUP BY UserId
),
HighReputationUsers AS (
    SELECT 
        Id, 
        DisplayName, 
        Reputation
    FROM 
        Users
    WHERE
        Reputation > 10000
),
ActiveUsers AS (
    SELECT 
        U.Id, 
        U.DisplayName
    FROM 
        Users U
    JOIN 
        Posts P ON U.Id = P.OwnerUserId
    WHERE 
        P.LastActivityDate > CURRENT_DATE - INTERVAL '1 year'
    GROUP BY 
        U.Id, U.DisplayName
    HAVING 
        COUNT(P.Id) > 10
),
TopPosts AS (
    SELECT 
        P.Id AS PostId,
        P.Title,
        P.Tags,
        P.Score,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC) AS Rank
    FROM 
        Posts P
    WHERE 
        P.PostTypeId = 1
),
DetailedViews AS (
    SELECT 
        PH.PostId, 
        COUNT(PH.Id) AS Edits
    FROM 
        PostHistory PH
    JOIN 
        PostHistoryTypes PHT ON PH.PostHistoryTypeId = PHT.Id
    WHERE 
        PHT.Name LIKE 'Edit%'
    GROUP BY 
        PH.PostId
)
SELECT 
    U.Id AS UserId,
    U.DisplayName,
    COALESCE(BS.TotalBadges, 0) AS TotalBadges,
    COALESCE(BS.GoldBadges, 0) AS GoldBadges,
    COALESCE(BS.SilverBadges, 0) AS SilverBadges,
    COALESCE(BS.BronzeBadges, 0) AS BronzeBadges,
    HV.TopTitle AS TopPostTitle,
    HV.TopScore AS TopPostScore,
    D.Edits AS TotalPostEdits
FROM 
    Users U
LEFT JOIN 
    BadgeStats BS ON U.Id = BS.UserId
LEFT OUTER JOIN (
    SELECT 
        HP.OwnerUserId, 
        HP.Title AS TopTitle,
        HP.Score AS TopScore
    FROM 
        TopPosts HP
    WHERE 
        HP.Rank = 1
) HV ON U.Id = HV.OwnerUserId
LEFT JOIN 
    (SELECT PostId, MAX(Edits) AS Edits FROM DetailedViews GROUP BY PostId) D ON D.PostId = HV.OwnerUserId
WHERE 
    U.Reputation > 5000
    AND U.Id IN (SELECT Id FROM HighReputationUsers)
    AND U.Id IN (SELECT Id FROM ActiveUsers)
ORDER BY 
    U.Reputation DESC;

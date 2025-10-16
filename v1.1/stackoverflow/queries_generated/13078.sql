-- {"query": "13078.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2142, "output_tokens": 661} 

WITH UserActivity AS (
    SELECT 
        OwnerUserId, 
        COUNT(*) AS TotalPosts,
        SUM(Score) AS TotalScore,
        AVG(Score) AS AvgScore,
        MAX(LastActivityDate) AS LastActivityDate
    FROM Posts
    WHERE OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
),
TopUsers AS (
    SELECT 
        U.Id,
        U.DisplayName,
        U.Reputation,
        UA.TotalPosts,
        UA.TotalScore,
        UA.AvgScore,
        UA.LastActivityDate,
        RANK() OVER (ORDER BY UA.TotalScore DESC) AS Rank
    FROM Users U
    LEFT JOIN UserActivity UA ON U.Id = UA.OwnerUserId
    WHERE U.Reputation > 1000 AND UA.LastActivityDate > CURRENT_TIMESTAMP - INTERVAL '6 months'
),
BadgeCounts AS (
    SELECT 
        UserId,
        COUNT(*) FILTER (WHERE Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE Class = 3) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
),
ComplexCalculations AS (
    SELECT 
        TU.Id,
        TU.DisplayName,
        TU.Reputation,
        TU.TotalPosts,
        TU.TotalScore,
        TU.AvgScore,
        TU.LastActivityDate,
        BC.GoldBadges,
        BC.SilverBadges,
        BC.BronzeBadges,
        (TU.Reputation * 0.1 + COALESCE(TU.TotalScore, 0) * 0.5 + COALESCE(BC.GoldBadges, 0) * 5 + COALESCE(BC.SilverBadges, 0) * 2 + COALESCE(BC.BronzeBadges, 0)) AS UserMetric
    FROM TopUsers TU
    LEFT JOIN BadgeCounts BC ON TU.Id = BC.UserId
    WHERE TU.Rank <= 100
)
SELECT 
    CC.Id,
    CC.DisplayName,
    CC.Reputation,
    CC.TotalPosts,
    CC.TotalScore,
    CC.AvgScore,
    CC.GoldBadges,
    CC.SilverBadges,
    CC.BronzeBadges,
    CC.UserMetric,
    (SELECT COUNT(*) FROM Comments C WHERE C.UserId = CC.Id AND C.CreationDate > CURRENT_TIMESTAMP - INTERVAL '1 year') AS CommentsLastYear,
    (SELECT COUNT(*) FROM Posts P WHERE P.OwnerUserId = CC.Id AND P.CreationDate > CURRENT_TIMESTAMP - INTERVAL '1 year') AS PostsLastYear
FROM ComplexCalculations CC
ORDER BY CC.UserMetric DESC;

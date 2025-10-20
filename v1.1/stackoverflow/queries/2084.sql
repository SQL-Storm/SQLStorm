WITH UserActivity AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COUNT(DISTINCT V.Id) AS TotalVotes,
        AVG(P.Score) AS AvgPostScore,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        DENSE_RANK() OVER (ORDER BY U.Reputation DESC) AS ReputationRank
    FROM 
        Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes V ON U.Id = V.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation
),
HighRatedPosts AS (
    SELECT
        P.Id,
        P.Title,
        P.Score,
        P.OwnerUserId,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.Id ASC) AS PostRank
    FROM 
        Posts P
    WHERE 
        P.Score > 50
)
SELECT 
    UA.UserId,
    UA.DisplayName,
    UA.TotalPosts,
    UA.TotalComments,
    UA.TotalVotes,
    UA.AvgPostScore,
    CONCAT(GREATEST(UA.GoldBadges, 0), '-', GREATEST(UA.SilverBadges, 0), '-', GREATEST(UA.BronzeBadges, 0)) AS BadgeSummary,
    COALESCE(HR.Title, 'No High-Rated Post') AS TopRatedPost,
    UA.ReputationRank
FROM 
    UserActivity UA
LEFT JOIN HighRatedPosts HR ON UA.UserId = HR.OwnerUserId AND HR.PostRank = 1
WHERE 
    UA.TotalPosts > 10
ORDER BY 
    UA.ReputationRank;
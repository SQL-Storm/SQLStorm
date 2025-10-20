SELECT 
    U.Id,
    U.DisplayName,
    COUNT(DISTINCT P.Id) AS TotalPosts,
    SUM(P.Score) AS TotalScore,
    MAX(P.Score) AS HighestScorePost,
    COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
    AVG(P.ViewCount) AS AvgViewCount,
    COUNT(DISTINCT B.Id) AS TotalBadges,
    SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
    COALESCE((SELECT COUNT(*) FROM Comments C WHERE C.UserId = U.Id), 0) AS TotalComments,
    COALESCE((SELECT COUNT(*) FROM Votes V WHERE V.UserId = U.Id AND V.VoteTypeId = 2), 0) AS TotalUpvotesGiven,
    COALESCE((SELECT COUNT(*) FROM Votes V2 WHERE V2.UserId = U.Id AND V2.VoteTypeId = 3), 0) AS TotalDownvotesGiven
FROM 
    Users U
LEFT JOIN 
    Posts P ON U.Id = P.OwnerUserId
LEFT JOIN 
    Badges B ON U.Id = B.UserId
WHERE 
    U.Reputation > 1000
    AND (P.CreationDate >= (DATE_TRUNC('month', CAST('2024-10-01' AS date)) - INTERVAL '6 months') OR P.Id IS NULL)
GROUP BY 
    U.Id,
    U.DisplayName
ORDER BY 
    TotalScore DESC,
    TotalBadges DESC
LIMIT 10;
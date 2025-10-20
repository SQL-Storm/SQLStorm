-- {"query": "43044.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 399} 

SELECT 
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
    (SELECT COUNT(*) FROM Comments WHERE UserId = U.Id) AS TotalComments,
    (SELECT COUNT(*) FROM Votes WHERE UserId = U.Id AND VoteTypeId = 2) AS TotalUpvotesGiven,
    (SELECT COUNT(*) FROM Votes WHERE UserId = U.Id AND VoteTypeId = 3) AS TotalDownvotesGiven
FROM 
    Users U
LEFT JOIN 
    Posts P ON U.Id = P.OwnerUserId
LEFT JOIN 
    Badges B ON U.Id = B.UserId
WHERE 
    U.Reputation > 1000
    AND P.CreationDate >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '6 months'
GROUP BY 
    U.DisplayName
ORDER BY 
    TotalScore DESC, TotalBadges DESC
LIMIT 10;

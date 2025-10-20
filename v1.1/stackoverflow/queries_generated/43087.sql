-- {"query": "43087.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 411} 

SELECT 
    U.DisplayName,
    U.Reputation,
    COUNT(DISTINCT P.Id) AS TotalPosts,
    SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS TotalGoldBadges,
    SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS TotalSilverBadges,
    SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS TotalBronzeBadges,
    AVG(P.Score) AS AvgScore,
    MAX(P.Score) AS MaxScore,
    (SELECT COUNT(*) FROM Comments C WHERE C.UserId = U.Id) AS TotalComments,
    (SELECT COUNT(*) FROM PostHistory PH WHERE PH.UserId = U.Id AND PH.PostHistoryTypeId IN (5, 24)) AS TotalEdits,
    (SELECT COUNT(*) FROM Votes V WHERE V.UserId = U.Id AND V.VoteTypeId = 2) AS TotalUpvotesGiven,
    (SELECT COUNT(*) FROM Votes V WHERE V.UserId = U.Id AND V.VoteTypeId = 3) AS TotalDownvotesGiven
FROM 
    Users U
LEFT JOIN 
    Posts P ON U.Id = P.OwnerUserId
LEFT JOIN 
    Badges B ON U.Id = B.UserId
WHERE 
    U.LastAccessDate > NOW() - INTERVAL '1 YEAR'
GROUP BY 
    U.Id
ORDER BY 
    TotalPosts DESC, TotalGoldBadges DESC
LIMIT 100;

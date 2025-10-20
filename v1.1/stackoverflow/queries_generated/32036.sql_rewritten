-- {"query": "32036.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 252} 
SELECT 
    U.Id AS UserId, 
    U.DisplayName, 
    SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    AVG(P.Score) AS AvgScore,
    SUM(P.ViewCount) AS TotalViews,
    COUNT(DISTINCT B.Id) AS TotalBadges,
    COUNT(DISTINCT V.Id) AS TotalUpVotesReceived,
    COUNT(DISTINCT C.Id) AS TotalCommentsMade,
    MAX(P.CreationDate) AS MostRecentPostDate
FROM 
    Users U
LEFT JOIN 
    Posts P ON P.OwnerUserId = U.Id
LEFT JOIN 
    Badges B ON B.UserId = U.Id
LEFT JOIN 
    Votes V ON V.PostId = P.Id AND V.VoteTypeId = 2
LEFT JOIN 
    Comments C ON C.UserId = U.Id
WHERE 
    U.Reputation >= 1000
GROUP BY 
    U.Id, U.DisplayName
ORDER BY 
    TotalQuestions DESC, AvgScore DESC
LIMIT 100;
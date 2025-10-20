-- {"query": "41078.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 648} 
SELECT 
    U.DisplayName AS UserName,
    COUNT(DISTINCT P.Id) AS TotalPosts,
    AVG(P.Score) AS AverageScore,
    SUM(P.ViewCount) AS TotalViews,
    SUM(P.CommentCount) AS TotalComments,
    SUM(P.FavoriteCount) AS TotalFavorites,
    COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN V.VoteTypeId = 2 THEN V.PostId END) AS TotalUpvotes,
    COUNT(DISTINCT CASE WHEN V.VoteTypeId = 3 THEN V.PostId END) AS TotalDownvotes,
    COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 AND P.AcceptedAnswerId IS NOT NULL THEN P.Id END) AS QuestionsWithAcceptedAnswer,
    COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 AND P.Score > 0 THEN P.Id END) AS PositiveScoredAnswers,
    COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 AND P.Score < 0 THEN P.Id END) AS NegativeScoredAnswers,
    COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 AND P.Score = 0 THEN P.Id END) AS ZeroScoredAnswers,
    COUNT(DISTINCT CASE WHEN C.PostId IS NOT NULL THEN C.Id END) AS TotalCommentsOnPosts,
    COUNT(DISTINCT CASE WHEN PH.PostId IS NOT NULL THEN PH.Id END) AS TotalPostRevisions,
    COUNT(DISTINCT CASE WHEN PL.PostId IS NOT NULL THEN PL.Id END) AS TotalLinkedPosts,
    COUNT(DISTINCT CASE WHEN B.UserId = U.Id THEN B.Id END) AS TotalBadges
FROM 
    Users U
LEFT JOIN 
    Posts P ON U.Id = P.OwnerUserId
LEFT JOIN 
    Votes V ON P.Id = V.PostId
LEFT JOIN 
    Comments C ON P.Id = C.PostId
LEFT JOIN 
    PostHistory PH ON P.Id = PH.PostId
LEFT JOIN 
    PostLinks PL ON P.Id = PL.PostId
LEFT JOIN 
    Badges B ON U.Id = B.UserId
GROUP BY 
    U.DisplayName
ORDER BY 
    TotalPosts DESC, 
    AverageScore DESC, 
    TotalViews DESC, 
    TotalComments DESC, 
    TotalFavorites DESC, 
    TotalQuestions DESC, 
    TotalAnswers DESC, 
    TotalUpvotes DESC, 
    TotalDownvotes DESC, 
    QuestionsWithAcceptedAnswer DESC, 
    PositiveScoredAnswers DESC, 
    NegativeScoredAnswers DESC, 
    ZeroScoredAnswers DESC, 
    TotalCommentsOnPosts DESC, 
    TotalPostRevisions DESC, 
    TotalLinkedPosts DESC, 
    TotalBadges DESC;
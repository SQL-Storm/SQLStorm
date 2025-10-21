-- {"query": "41064.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 659} 
SELECT 
    U.DisplayName AS UserName,
    COUNT(DISTINCT P.Id) AS TotalPosts,
    AVG(P.Score) AS AverageScore,
    SUM(P.ViewCount) AS TotalViews,
    SUM(P.CommentCount) AS TotalComments,
    SUM(P.FavoriteCount) AS TotalFavorites,
    COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 AND P.ClosedDate IS NOT NULL THEN P.Id END) AS ClosedQuestions,
    COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 AND P.Score > 0 THEN P.Id END) AS UpvotedAnswers,
    COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 AND P.AcceptedAnswerId IS NOT NULL THEN P.Id END) AS AnsweredQuestions,
    COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 AND P.AnswerCount > 0 THEN P.Id END) AS QuestionsWithAnswers,
    COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 AND P.FavoriteCount > 0 THEN P.Id END) AS FavoritedQuestions,
    COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 AND P.Score < 0 THEN P.Id END) AS DownvotedAnswers,
    COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 AND P.ViewCount > 1000 THEN P.Id END) AS HighlyViewedQuestions,
    COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 AND P.ViewCount > 500 THEN P.Id END) AS ModeratelyViewedAnswers,
    COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 AND P.CreationDate > DATE_TRUNC('month', cast('2024-10-01' as date)) THEN P.Id END) AS QuestionsThisMonth,
    COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 AND P.CreationDate > DATE_TRUNC('month', cast('2024-10-01' as date)) THEN P.Id END) AS AnswersThisMonth,
    COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 AND P.Tags LIKE '%SQL%' THEN P.Id END) AS SQLQuestions,
    COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 AND P.Tags LIKE '%SQL%' THEN P.Id END) AS SQLAnswers,
    COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 AND P.CreationDate > DATE_TRUNC('year', cast('2024-10-01' as date)) THEN P.Id END) AS AnswersThisYear
FROM 
    Users U
JOIN 
    Posts P ON U.Id = P.OwnerUserId
JOIN 
    Votes V ON P.Id = V.PostId
GROUP BY 
    U.DisplayName
ORDER BY 
    TotalPosts DESC, 
    AverageScore DESC, 
    TotalViews DESC, 
    TotalComments DESC, 
    TotalFavorites DESC
LIMIT 10;
-- {"query": "41004.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 309} 
SELECT 
    U.DisplayName AS UserDisplayName, 
    COUNT(P.Id) AS TotalPosts, 
    AVG(P.Score) AS AverageScore, 
    SUM(P.ViewCount) AS TotalViews, 
    SUM(P.CommentCount) AS TotalComments, 
    SUM(P.FavoriteCount) AS TotalFavorites,
    CASE 
        WHEN MAX(P.CreationDate) > DATE_TRUNC('month', cast('2024-10-01' as date)) - INTERVAL '1 month' 
        THEN COUNT(P.Id) 
        ELSE 0 
    END AS PostsLastMonth,
    CASE 
        WHEN MAX(P.CreationDate) > DATE_TRUNC('year', cast('2024-10-01' as date)) - INTERVAL '1 year' 
        THEN COUNT(P.Id) 
        ELSE 0 
    END AS PostsLastYear
FROM 
    Users U
JOIN 
    Posts P ON U.Id = P.OwnerUserId
JOIN 
    PostTypes PT ON P.PostTypeId = PT.Id
JOIN 
    Tags T ON P.Id = T.ExcerptPostId
JOIN 
    Votes V ON P.Id = V.PostId
WHERE 
    PT.Name IN ('Question', 'Answer')
    AND V.VoteTypeId IN (2, 3)
GROUP BY 
    U.DisplayName
ORDER BY 
    TotalPosts DESC, 
    AverageScore DESC;
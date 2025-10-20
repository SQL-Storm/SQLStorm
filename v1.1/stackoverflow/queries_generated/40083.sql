-- {"query": "40083.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 211} 

SELECT 
    COUNT(DISTINCT Post.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN Post.PostTypeId = 1 THEN Post.Id ELSE NULL END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN Post.PostTypeId = 2 THEN Post.Id ELSE NULL END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN Post.Score > 100 THEN Post.Id ELSE NULL END) AS HighScorePosts,
    COUNT(DISTINCT CASE WHEN Users.Reputation > 10000 THEN Users.Id ELSE NULL END) AS HighReputationUsers,
    COUNT(DISTINCT Badges.Id) AS TotalBadges
FROM 
    Posts AS Post
JOIN 
    Users ON Post.OwnerUserId = Users.Id
LEFT JOIN 
    Badges ON Users.Id = Badges.UserId
WHERE 
    Post.CreationDate >= DATE_TRUNC('month', CURRENT_TIMESTAMP) - INTERVAL '1 year';

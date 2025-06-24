
SELECT 
    Users.DisplayName,
    COUNT(Posts.Id) AS NumberOfPosts,
    SUM(CASE WHEN Posts.PostTypeId = 1 THEN 1 ELSE 0 END) AS NumberOfQuestions,
    SUM(CASE WHEN Posts.PostTypeId = 2 THEN 1 ELSE 0 END) AS NumberOfAnswers,
    SUM(Posts.ViewCount) AS TotalViews
FROM 
    Users
LEFT JOIN 
    Posts ON Users.Id = Posts.OwnerUserId
GROUP BY 
    Users.DisplayName
ORDER BY 
    NumberOfPosts DESC
OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY;

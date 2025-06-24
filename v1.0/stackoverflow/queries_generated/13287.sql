-- Performance Benchmarking Query

-- This query retrieves the total number of posts per post type, 
-- the average score of those posts, and the count of comments for each post type
WITH PostStats AS (
    SELECT 
        pt.Name AS PostType,
        COUNT(p.Id) AS TotalPosts,
        AVG(p.Score) AS AverageScore,
        SUM(COALESCE(c.CommentCount, 0)) AS TotalComments
    FROM 
        Posts p
    JOIN 
        PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN (
        SELECT 
            PostId, 
            COUNT(Id) AS CommentCount 
        FROM 
            Comments 
        GROUP BY 
            PostId
    ) c ON p.Id = c.PostId
    GROUP BY 
        pt.Name
)

SELECT 
    PostType, 
    TotalPosts, 
    AverageScore, 
    TotalComments 
FROM 
    PostStats
ORDER BY 
    TotalPosts DESC;

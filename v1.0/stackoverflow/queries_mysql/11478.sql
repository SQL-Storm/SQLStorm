
WITH PostStats AS (
    SELECT 
        pt.Name AS PostType,
        COUNT(p.Id) AS TotalPosts,
        COUNT(DISTINCT p.OwnerUserId) AS UniqueUsers,
        SUM(p.ViewCount) AS TotalViews,
        AVG(p.Score) AS AverageScore,
        AVG(p.AnswerCount) AS AverageAnswers,
        AVG(p.CommentCount) AS AverageComments
    FROM 
        Posts p
    INNER JOIN 
        PostTypes pt ON p.PostTypeId = pt.Id
    GROUP BY 
        pt.Name
)
SELECT 
    PostType,
    TotalPosts,
    UniqueUsers,
    TotalViews,
    AverageScore,
    AverageAnswers,
    AverageComments,
    (@row_number:=@row_number + 1) AS Rank
FROM 
    PostStats, (SELECT @row_number := 0) AS rn
ORDER BY 
    TotalPosts DESC;

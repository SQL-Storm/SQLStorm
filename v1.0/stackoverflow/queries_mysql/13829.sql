
SELECT 
    pt.Name AS PostType, 
    COUNT(p.Id) AS TotalPosts, 
    AVG(p.Score) AS AverageScore, 
    AVG(p.ViewCount) AS AverageViewCount, 
    AVG(p.AnswerCount) AS AverageAnswerCount 
FROM 
    Posts p
JOIN 
    PostTypes pt ON p.PostTypeId = pt.Id 
GROUP BY 
    pt.Name, p.Score, p.ViewCount, p.AnswerCount 
ORDER BY 
    TotalPosts DESC;

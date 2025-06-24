
SELECT 
    pt.Name AS PostType, 
    COUNT(p.Id) AS PostCount, 
    AVG(p.Score) AS AverageScore, 
    SUM(COALESCE(c.CommentCount, 0)) AS TotalComments
FROM 
    Posts p
LEFT JOIN 
    PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN 
    (SELECT 
         PostId, 
         COUNT(Id) AS CommentCount 
     FROM 
         Comments 
     GROUP BY 
         PostId) c ON p.Id = c.PostId
GROUP BY 
    pt.Name, p.Id, p.Score
ORDER BY 
    PostCount DESC;

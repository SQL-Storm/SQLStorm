
WITH PostScoreViews AS (
    SELECT 
        pt.Name AS PostType,
        AVG(p.Score) AS AverageScore,
        AVG(u.Views) AS AverageViews
    FROM 
        Posts p
    JOIN 
        PostTypes pt ON p.PostTypeId = pt.Id
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.CreationDate >= '2024-10-01 12:34:56' - INTERVAL 1 YEAR  
    GROUP BY 
        pt.Name
)
SELECT 
    PostType,
    AverageScore,
    AverageViews
FROM 
    PostScoreViews
ORDER BY 
    AverageScore DESC;

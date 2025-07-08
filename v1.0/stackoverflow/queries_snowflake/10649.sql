
WITH PostStats AS (
    SELECT 
        pt.Name AS PostType,
        COUNT(p.Id) AS TotalPosts,
        AVG(p.Score) AS AverageScore,
        SUM(p.ViewCount) AS TotalViews
    FROM 
        Posts p
    JOIN 
        PostTypes pt ON p.PostTypeId = pt.Id
    GROUP BY 
        pt.Name
),
PostHistoryStats AS (
    SELECT 
        p.Id AS PostId,
        COUNT(ph.Id) AS RevisionCount
    FROM 
        Posts p
    LEFT JOIN 
        PostHistory ph ON p.Id = ph.PostId
    GROUP BY 
        p.Id
)
SELECT 
    ps.PostType,
    ps.TotalPosts,
    ps.AverageScore,
    ps.TotalViews,
    COALESCE(AVG(pHS.RevisionCount), 0) AS AverageRevisions
FROM 
    PostStats ps
LEFT JOIN 
    PostHistoryStats pHS ON pHS.PostId IN (
        SELECT Id 
        FROM Posts 
        WHERE PostTypeId = (SELECT Id FROM PostTypes WHERE Name = ps.PostType)
    )
GROUP BY 
    ps.PostType, ps.TotalPosts, ps.AverageScore, ps.TotalViews
ORDER BY 
    ps.TotalPosts DESC;

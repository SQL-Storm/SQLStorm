
SELECT 
    p.Id AS PostId, 
    p.Title AS PostTitle, 
    u.DisplayName AS AuthorName, 
    p.CreationDate AS PostDate, 
    p.ViewCount AS NumberOfViews, 
    p.Score AS PostScore
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
WHERE 
    p.PostTypeId = 1  
GROUP BY 
    p.Id, p.Title, u.DisplayName, p.CreationDate, p.ViewCount, p.Score
ORDER BY 
    p.CreationDate DESC
LIMIT 10;

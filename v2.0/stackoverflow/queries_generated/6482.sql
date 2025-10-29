-- {"query": "6482.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 443} 

SELECT 
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS TotalAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id ELSE NULL END) AS TotalWikis,
    SUM(p.Score) AS TotalScore,
    SUM(p.ViewCount) AS TotalViews,
    MAX(p.LastActivityDate) AS LastActivity,
    MIN(p.CreationDate) AS FirstPost,
    MAX(p.CreationDate) AS LastPost,
    b.Class,
    b.TagBased
FROM 
    Users u
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    (SELECT 
         ph.PostId,
         MAX(CASE WHEN ph.PostHistoryTypeId = 1 THEN ph.RevisionGUID ELSE NULL END) AS LatestTitle,
         MAX(CASE WHEN ph.PostHistoryTypeId = 2 THEN ph.RevisionGUID ELSE NULL END) AS LatestBody,
         MAX(CASE WHEN ph.PostHistoryTypeId = 5 THEN ph.RevisionGUID ELSE NULL END) AS LatestBodyEdit
     FROM 
         PostHistory ph
     GROUP BY 
         ph.PostId) ph ON p.Id = ph.PostId
WHERE 
    u.Reputation > 10000
    AND u.Id NOT IN (
        SELECT 
            DISTINCT UserId 
        FROM 
            Comments 
        WHERE 
            Text LIKE '%spam%'
    )
GROUP BY 
    u.Id, b.Id
HAVING 
    COUNT(DISTINCT p.Id) > 100
ORDER BY 
    u.Reputation DESC, TotalScore DESC
LIMIT 100;

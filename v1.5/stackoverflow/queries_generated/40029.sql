-- {"query": "40029.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-micro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 202} 

SELECT 
    COUNT(DISTINCT p.Id) AS PostCount,
    COUNT(DISTINCT u.Id) AS UserCount,
    SUM(p.Score) AS TotalScore,
    AVG(p.Score) AS AvgScore,
    COUNT(DISTINCT CASE WHEN b.Id IS NOT NULL THEN u.Id ELSE NULL END) AS BadgeUserCount
FROM 
    Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON u.Id = b.UserId
WHERE 
    p.PostTypeId = 1
    AND p.CreationDate >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '6 months'
GROUP BY 
    EXTRACT(YEAR FROM p.CreationDate), 
    EXTRACT(MONTH FROM p.CreationDate)
ORDER BY 
    EXTRACT(YEAR FROM p.CreationDate), 
    EXTRACT(MONTH FROM p.CreationDate) DESC;

-- {"query": "42049.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 437} 
SELECT 
    u.DisplayName,
    COUNT(p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
    SUM(p.Score) AS TotalScore,
    COUNT(DISTINCT ph.Id) AS TotalEdits,
    COUNT(DISTINCT v.Id) AS TotalVotes,
    AVG(LENGTH(p.Body)) AS AvgPostLength,
    COUNT(DISTINCT ph.PostHistoryTypeId) AS UniqueEditTypes,
    COUNT(DISTINCT ph.UserId) AS UniqueEditors,
    COUNT(DISTINCT c.Id) AS TotalComments,
    SUM(CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13) THEN 1 ELSE 0 END) AS ModerationActions,
    COUNT(DISTINCT b.Id) AS TotalBadges,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
FROM 
    Users u
JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Comments c ON p.Id = c.PostId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
WHERE 
    u.CreationDate <= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
GROUP BY 
    u.DisplayName
HAVING 
    COUNT(p.Id) > 10
ORDER BY 
    TotalScore DESC, 
    TotalPosts DESC
LIMIT 100;
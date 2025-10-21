SELECT 
    t.tag_name,
    u.DisplayName,
    u.Location,
    u.Reputation,
    SUM(p.Score) AS total_score,
    COUNT(*) AS post_count,
    AVG(p.Score) AS avg_score,
    RANK() OVER (PARTITION BY t.tag_name ORDER BY SUM(p.Score) DESC) AS rank_within_tag
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
CROSS JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS t(tag_name)
WHERE 
    p.PostTypeId = 2
    AND p.CreationDate >= TIMESTAMP '2023-01-01 00:00:00'
    AND p.CreationDate < TIMESTAMP '2024-01-01 00:00:00'
    AND p.Score > 0
    AND u.Reputation > 100
GROUP BY 
    t.tag_name, u.Id, u.DisplayName, u.Location, u.Reputation
HAVING 
    COUNT(*) >= 5
    AND SUM(p.Score) >= 100
ORDER BY 
    t.tag_name, rank_within_tag
LIMIT 10000;
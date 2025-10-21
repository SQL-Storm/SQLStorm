-- {"query": "52090.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 247} 
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
    p.PostTypeId = 2  -- Answers
    AND p.CreationDate >= '2023-01-01'::timestamp
    AND p.CreationDate < '2024-01-01'::timestamp
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
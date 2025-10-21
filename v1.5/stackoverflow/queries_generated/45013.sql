-- {"query": "45013.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 370}
SELECT 
    p.Id AS PostId, 
    p.Title, 
    p.Score, 
    p.ViewCount, 
    u.DisplayName, 
    u.Reputation,
    t.TagName,
    COUNT(DISTINCT c.Id) AS CommentCount,
    COUNT(DISTINCT v.Id) AS VoteCount,
    AVG(v.BountyAmount) AS AvgBountyAmount,
    DENSE_RANK() OVER (PARTITION BY t.TagName ORDER BY p.Score DESC) AS ScoreRank
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
JOIN 
    (SELECT UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName) st
JOIN 
    Tags t ON st.TagName = t.TagName
LEFT JOIN 
    Comments c ON p.Id = c.PostId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
WHERE 
    p.PostTypeId = 1 
    AND u.Reputation > 1000 
    AND p.Score > 10
GROUP BY 
    p.Id, p.Title, p.Score, p.ViewCount, u.DisplayName, u.Reputation, t.TagName
HAVING 
    COUNT(DISTINCT c.Id) > 5
ORDER BY 
    ScoreRank, p.Score DESC
LIMIT 500;

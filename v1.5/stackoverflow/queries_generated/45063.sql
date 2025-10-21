-- {"query": "45063.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 144522, "output_tokens": 25571} 
SELECT 
    p.Id AS PostId,
    p.Title,
    u.DisplayName AS AuthorName,
    t.TagName,
    COUNT(DISTINCT c.Id) AS CommentCount,
    COUNT(DISTINCT v.Id) AS VoteCount,
    AVG(v.Score) AS AverageVoteScore,
    p.CreationDate,
    DENSE_RANK() OVER (PARTITION BY t.TagName ORDER BY p.Score DESC) AS TagPostRank
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
JOIN 
    Tags t ON EXISTS (SELECT 1 FROM unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag WHERE tag = t.TagName)
LEFT JOIN 
    Comments c ON p.Id = c.PostId
LEFT JOIN 
    Votes v ON p.Id = v.PostId
WHERE 
    p.PostTypeId = 1 
    AND u.Reputation > 1000
    AND p.CreationDate > '2020-01-01'
GROUP BY 
    p.Id, p.Title, u.DisplayName, t.TagName, p.CreationDate
HAVING 
    COUNT(DISTINCT v.Id) > 10
ORDER BY 
    TagPostRank, VoteCount DESC
LIMIT 500;
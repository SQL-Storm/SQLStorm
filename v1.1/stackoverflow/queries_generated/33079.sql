-- {"query": "33079.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 331} 
SELECT 
    p.PostTypeId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    t.TagName,
    u.DisplayName AS OwnerName,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    COUNT(DISTINCT c.Id) AS CommentCount,
    COUNT(CASE WHEN pl.RelatedPostId IS NOT NULL THEN 1 END) AS LinkedPostsCount,
    SUM(CASE WHEN v.VoteTypeId IN (2,3) THEN 1 ELSE 0 END) AS TotalVotes
FROM 
    Posts p
LEFT JOIN 
    PostTags pt ON p.Id = pt.PostId
LEFT JOIN 
    Tags t ON pt.TagId = t.Id
LEFT JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Comments c ON p.Id = c.PostId
LEFT JOIN 
    PostLinks pl ON p.Id = pl.PostId
WHERE 
    p.PostTypeId IN (1,2)
    AND p.CreationDate BETWEEN NOW() - INTERVAL '1 year' AND NOW()
GROUP BY 
    p.PostTypeId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    t.TagName,
    u.DisplayName
ORDER BY 
    TotalVotes DESC
LIMIT 100;
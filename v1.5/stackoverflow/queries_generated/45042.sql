-- {"query": "45042.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 96348, "output_tokens": 17094} 
SELECT
    p.Id AS PostId,
    p.Title,
    u.DisplayName AS UserName,
    COUNT(DISTINCT c.Id) AS CommentCount,
    COUNT(DISTINCT pl.Id) AS RelatedPostsCount,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) OVER () AS MedianScore
FROM 
    Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
WHERE 
    p.CreationDate > (SELECT AVG(CreationDate) FROM Posts)
    AND u.Reputation > 1000
GROUP BY 
    p.Id, p.Title, u.DisplayName
ORDER BY 
    UpVotes - DownVotes DESC
LIMIT 500;
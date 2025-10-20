-- {"query": "32045.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 271} 
SELECT
    p.Id AS PostId,
    t.TagName,
    AVG(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS AvgUpVotes,
    AVG(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS AvgDownVotes,
    MAX(ph.CreationDate) AS LastEdited,
    COUNT(DISTINCT c.Id) AS CommentCount,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13) THEN ph.Id ELSE NULL END) AS CloseReopenDeleteUndeleteCount
FROM
    Posts p
LEFT JOIN 
    Tags t ON p.Tags LIKE '%' || t.TagName || '%'
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
LEFT JOIN 
    Comments c ON p.Id = c.PostId
WHERE
    p.PostTypeId = 1
GROUP BY
    p.Id, t.TagName
ORDER BY
    AVG(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) DESC,
    COUNT(DISTINCT c.Id) DESC,
    MAX(ph.CreationDate) DESC;
-- {"query": "42082.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 486} 

SELECT 
    p.Id,
    p.Title,
    p.Score,
    u.DisplayName AS Author,
    COUNT(v.Id) AS VoteCount,
    COUNT(c.Id) AS CommentCount,
    COUNT(ph.Id) AS EditCount,
    COUNT(DISTINCT ph.UserId) AS UniqueEditors,
    COUNT(DISTINCT v.UserId) AS UniqueVoters,
    COUNT(DISTINCT ph.PostHistoryTypeId) AS UniqueEditTypes,
    COUNT(DISTINCT ph.CreationDate) AS EditDays,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20, 35) THEN ph.Id END) AS SignificantEdits,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20, 35) THEN ph.UserId END) AS UniqueSignificantEditors,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId IN (2, 3) THEN v.Id END) AS UpDownVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId IN (2, 3) THEN v.UserId END) AS UniqueUpDownVoters,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 4 THEN v.Id END) AS OffensiveVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 4 THEN v.UserId END) AS UniqueOffensiveVoters
FROM 
    Posts p
JOIN 
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
    Votes v ON p.Id = v.PostId
LEFT JOIN 
    Comments c ON p.Id = c.PostId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
WHERE 
    p.PostTypeId = 1
    AND p.CreationDate >= NOW() - INTERVAL '1 year'
GROUP BY 
    p.Id
ORDER BY 
    p.Score DESC, 
    VoteCount DESC, 
    CommentCount DESC, 
    EditCount DESC
LIMIT 100;

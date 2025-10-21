-- {"query": "56001.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 233} 
SELECT 
    u.Id, 
    u.Reputation, 
    u.DisplayName, 
    p.Id AS PostId, 
    p.Score, 
    p.ViewCount, 
    p.AnswerCount, 
    p.CommentCount, 
    ph.PostHistoryTypeId, 
    ph.CreationDate AS PostHistoryCreationDate, 
    v.VoteTypeId, 
    v.CreationDate AS VoteCreationDate
FROM 
    Users u
INNER JOIN 
    Posts p ON u.Id = p.OwnerUserId
INNER JOIN 
    PostHistory ph ON p.Id = ph.PostId
INNER JOIN 
    Votes v ON p.Id = v.PostId
WHERE 
    u.Reputation > 1000 
    AND p.Score > 10 
    AND ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15) 
    AND v.VoteTypeId IN (2, 3)
ORDER BY 
    u.Reputation DESC, 
    p.Score DESC, 
    ph.CreationDate DESC, 
    v.CreationDate DESC
LIMIT 100;
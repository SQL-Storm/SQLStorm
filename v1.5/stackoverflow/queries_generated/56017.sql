-- {"query": "56017.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 169} 

SELECT 
    p.Id, 
    p.Title, 
    p.Score, 
    p.ViewCount, 
    p.AnswerCount, 
    ph.PostHistoryTypeId, 
    ph.UserId, 
    ph.CreationDate, 
    u.DisplayName, 
    u.Reputation
FROM 
    Posts p
JOIN 
    PostHistory ph ON p.Id = ph.PostId
JOIN 
    Users u ON ph.UserId = u.Id
WHERE 
    p.PostTypeId = 1 
    AND ph.PostHistoryTypeId IN (10, 11)
    AND p.Score > 10 
    AND p.ViewCount > 1000
    AND u.Reputation > 1000
ORDER BY 
    p.Score DESC, 
    p.ViewCount DESC, 
    u.Reputation DESC;

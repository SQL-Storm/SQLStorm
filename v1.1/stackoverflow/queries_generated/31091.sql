-- {"query": "31091.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 433} 

WITH RankedPosts AS (
  SELECT 
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    u.DisplayName AS OwnerDisplayName,
    COUNT(DISTINCT c.Id) AS CommentCount,
    COUNT(DISTINCT a.Id) AS AnswerCount,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS Rank
  FROM 
    Posts p
  LEFT JOIN 
    Users u ON p.OwnerUserId = u.Id
  LEFT JOIN 
    Comments c ON p.Id = c.PostId
  LEFT JOIN 
    Posts a ON a.ParentId = p.Id AND p.PostTypeId = 1
  WHERE 
    p.CreationDate >= NOW() - INTERVAL '1 year' 
    AND p.PostTypeId = 1 -- only questions
  GROUP BY 
    p.Id, p.Title, p.CreationDate, p.Score, u.DisplayName
),
HighScoringPosts AS (
  SELECT 
    rp.PostId,
    rp.Title,
    rp.CreationDate,
    rp.Score,
    rp.OwnerDisplayName,
    rp.CommentCount,
    rp.AnswerCount
  FROM 
    RankedPosts rp
  WHERE 
    rp.Rank <= 5 -- top 5 posts by score for each user
)
SELECT 
  hsp.Title,
  hsp.OwnerDisplayName,
  hsp.Score,
  hsp.CommentCount,
  hsp.AnswerCount,
  ph.Name AS PostHistoryTypeName,
  COUNT(ph.Id) AS HistoryActionCount
FROM 
  HighScoringPosts hsp
LEFT JOIN 
  PostHistory ph ON hsp.PostId = ph.PostId
WHERE 
  ph.CreationDate >= NOW() - INTERVAL '30 days' -- history in the last month
GROUP BY 
  hsp.Title, hsp.OwnerDisplayName, hsp.Score, hsp.CommentCount, hsp.AnswerCount, ph.Name
ORDER BY 
  hsp.Score DESC, hsp.Title ASC;

-- {"query": "26024.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 551} 

WITH RankedPosts AS (
  SELECT 
    p.Id, 
    p.Score, 
    p.ViewCount, 
    p.Title, 
    p.Tags, 
    ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS RowNum,
    LAG(p.Score, 1, 0) OVER (ORDER BY p.Score DESC) AS PrevScore,
    LEAD(p.Score, 1, 0) OVER (ORDER BY p.Score DESC) AS NextScore
  FROM 
    Posts p
  WHERE 
    p.PostTypeId = 1 AND p.Score > 0
),
TopPosts AS (
  SELECT 
    p.Id, 
    p.Score, 
    p.ViewCount, 
    p.Title, 
    p.Tags
  FROM 
    RankedPosts p
  WHERE 
    p.RowNum <= 10
),
PostWithBadges AS (
  SELECT 
    p.Id, 
    p.Score, 
    p.ViewCount, 
    p.Title, 
    p.Tags, 
    COUNT(DISTINCT b.Name) AS BadgeCount
  FROM 
    Posts p
  LEFT JOIN 
    Badges b ON p.OwnerUserId = b.UserId
  GROUP BY 
    p.Id, p.Score, p.ViewCount, p.Title, p.Tags
),
PostWithVotes AS (
  SELECT 
    p.Id, 
    p.Score, 
    p.ViewCount, 
    p.Title, 
    p.Tags, 
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
  FROM 
    Posts p
  LEFT JOIN 
    Votes v ON p.Id = v.PostId
  GROUP BY 
    p.Id, p.Score, p.ViewCount, p.Title, p.Tags
)
SELECT 
  tp.Id, 
  tp.Score, 
  tp.ViewCount, 
  tp.Title, 
  tp.Tags, 
  pwv.UpVotes, 
  pwv.DownVotes, 
  COALESCE(pwb.BadgeCount, 0) AS BadgeCount
FROM 
  TopPosts tp
LEFT JOIN 
  PostWithVotes pwv ON tp.Id = pwv.Id
LEFT JOIN 
  PostWithBadges pwb ON tp.Id = pwb.Id
WHERE 
  tp.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1)
  AND pwv.UpVotes > pwv.DownVotes
  AND pwb.BadgeCount > 1
ORDER BY 
  tp.Score DESC;

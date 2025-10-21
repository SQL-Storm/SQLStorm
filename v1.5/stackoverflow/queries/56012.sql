-- {"query": "56012.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 330} 
WITH TopPosts AS (
  SELECT 
    p.Id, 
    p.Score, 
    p.ViewCount, 
    p.Tags, 
    p.Title, 
    ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS RowNum
  FROM 
    Posts p
  WHERE 
    p.PostTypeId = 1
),
TopUsers AS (
  SELECT 
    u.Id, 
    u.Reputation, 
    u.DisplayName, 
    COUNT(DISTINCT p.Id) AS NumPosts
  FROM 
    Users u
  JOIN 
    Posts p ON u.Id = p.OwnerUserId
  WHERE 
    p.PostTypeId = 1
  GROUP BY 
    u.Id, u.Reputation, u.DisplayName
),
TopBadges AS (
  SELECT 
    b.UserId, 
    b.Name, 
    COUNT(DISTINCT b.Id) AS NumBadges
  FROM 
    Badges b
  GROUP BY 
    b.UserId, b.Name
)
SELECT 
  tp.Id, 
  tp.Score, 
  tp.ViewCount, 
  tp.Tags, 
  tp.Title, 
  tu.Reputation, 
  tu.DisplayName, 
  tu.NumPosts, 
  tb.NumBadges
FROM 
  TopPosts tp
JOIN 
  TopUsers tu ON tp.Id = tu.Id
JOIN 
  TopBadges tb ON tu.Id = tb.UserId
WHERE 
  tp.RowNum <= 10
  AND tu.NumPosts > 10
  AND tb.NumBadges > 5
ORDER BY 
  tp.Score DESC;
-- {"query": "26090.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 432} 

WITH TopUsers AS (
  SELECT 
    u.Id, 
    u.DisplayName, 
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes, 
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
  FROM 
    Users u
  LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
  LEFT JOIN 
    Votes v ON p.Id = v.PostId
  GROUP BY 
    u.Id, u.DisplayName
  HAVING 
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) > 1000
),
TopPosts AS (
  SELECT 
    p.Id, 
    p.Title, 
    p.Score, 
    p.ViewCount, 
    p.AnswerCount, 
    ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS RowNum
  FROM 
    Posts p
  WHERE 
    p.PostTypeId = 1 AND p.Score > 100
),
UserBadges AS (
  SELECT 
    u.Id, 
    COUNT(DISTINCT b.Name) AS BadgeCount
  FROM 
    Users u
  LEFT JOIN 
    Badges b ON u.Id = b.UserId
  GROUP BY 
    u.Id
)
SELECT 
  u.DisplayName, 
  u.Reputation, 
  tu.UpVotes, 
  tu.DownVotes, 
  ub.BadgeCount, 
  tp.Title, 
  tp.Score, 
  tp.ViewCount, 
  tp.AnswerCount
FROM 
  Users u
LEFT JOIN 
  TopUsers tu ON u.Id = tu.Id
LEFT JOIN 
  UserBadges ub ON u.Id = ub.Id
LEFT JOIN 
  Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
  TopPosts tp ON p.Id = tp.Id
WHERE 
  u.Reputation > 10000 AND tu.UpVotes > 1000
ORDER BY 
  u.Reputation DESC, tu.UpVotes DESC;

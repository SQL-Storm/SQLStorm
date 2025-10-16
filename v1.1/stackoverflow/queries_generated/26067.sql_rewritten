-- {"query": "26067.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 480} 
WITH TopUsers AS (
  SELECT 
    u.Id, 
    u.DisplayName, 
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesCount, 
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesCount
  FROM 
    Users u
  LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
  LEFT JOIN 
    Votes v ON p.Id = v.PostId
  WHERE 
    p.PostTypeId = 2
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
    ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS RowNum
  FROM 
    Posts p
  WHERE 
    p.PostTypeId = 1
  ORDER BY 
    p.Score DESC
),
UserBadges AS (
  SELECT 
    u.Id, 
    u.DisplayName, 
    COUNT(b.Id) AS BadgesCount
  FROM 
    Users u
  LEFT JOIN 
    Badges b ON u.Id = b.UserId
  GROUP BY 
    u.Id, u.DisplayName
)
SELECT 
  tu.DisplayName, 
  tu.UpVotesCount, 
  tu.DownVotesCount, 
  ub.BadgesCount, 
  tp.Title, 
  tp.Score, 
  tp.ViewCount
FROM 
  TopUsers tu
  LEFT JOIN UserBadges ub ON tu.Id = ub.Id
  LEFT JOIN (
    SELECT 
      p.Id, 
      p.Title, 
      p.Score, 
      p.ViewCount, 
      ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS RowNum
    FROM 
      Posts p
    WHERE 
      p.PostTypeId = 1
  ) tp ON tu.Id = tp.Id
WHERE 
  tu.UpVotesCount > 5000
  AND ub.BadgesCount > 10
  AND tp.RowNum <= 10
ORDER BY 
  tu.UpVotesCount DESC, 
  tp.Score DESC;
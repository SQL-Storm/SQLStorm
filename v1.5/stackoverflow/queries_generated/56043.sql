-- {"query": "56043.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 497} 

WITH TopUsers AS (
  SELECT 
    u.Id, 
    u.DisplayName, 
    COUNT(DISTINCT p.Id) AS PostCount, 
    SUM(p.Score) AS TotalScore, 
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount, 
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
  FROM 
    Users u
  JOIN 
    Posts p ON u.Id = p.OwnerUserId
  WHERE 
    p.PostTypeId IN (1, 2)
  GROUP BY 
    u.Id, u.DisplayName
  HAVING 
    COUNT(DISTINCT p.Id) > 100
),
TopTags AS (
  SELECT 
    t.TagName, 
    COUNT(DISTINCT p.Id) AS PostCount, 
    SUM(p.Score) AS TotalScore
  FROM 
    Tags t
  JOIN 
    Posts p ON t.Id = ANY(string_to_array(p.Tags, '><'))
  GROUP BY 
    t.TagName
  HAVING 
    COUNT(DISTINCT p.Id) > 50
),
TopPosts AS (
  SELECT 
    p.Id, 
    p.Title, 
    p.Score, 
    p.ViewCount, 
    p.AnswerCount, 
    p.CommentCount, 
    p.FavoriteCount
  FROM 
    Posts p
  WHERE 
    p.PostTypeId = 1 AND p.Score > 100
  ORDER BY 
    p.Score DESC
  LIMIT 100
)
SELECT 
  tu.DisplayName, 
  tu.PostCount, 
  tu.TotalScore, 
  tu.QuestionCount, 
  tu.AnswerCount, 
  tt.TagName, 
  tp.Title, 
  tp.Score, 
  tp.ViewCount, 
  tp.AnswerCount, 
  tp.CommentCount, 
  tp.FavoriteCount
FROM 
  TopUsers tu
JOIN 
  TopTags tt ON tu.Id = ANY(
    SELECT 
      u.Id
    FROM 
      Users u
    JOIN 
      Posts p ON u.Id = p.OwnerUserId
    WHERE 
      p.PostTypeId = 1 AND p.Tags LIKE '%' + tt.TagName + '%'
  )
JOIN 
  TopPosts tp ON tu.Id = tp.OwnerUserId
ORDER BY 
  tu.TotalScore DESC;

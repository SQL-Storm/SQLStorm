WITH TopUsers AS (
  SELECT 
    u.Id,
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS PostCount,
    SUM(p.Score) AS TotalScore,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
  FROM 
    Users AS u
  JOIN 
    Posts AS p ON u.Id = p.OwnerUserId
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
    Tags AS t
  JOIN 
    Posts AS p ON p.Tags LIKE '%' || t.TagName || '%'
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
    Posts AS p
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
  TopUsers AS tu
JOIN 
  TopTags AS tt
  ON EXISTS (
    SELECT 1
    FROM Users AS u
    JOIN Posts AS p ON u.Id = p.OwnerUserId
    WHERE u.Id = tu.Id
      AND p.PostTypeId = 1
      AND p.Tags LIKE '%' || tt.TagName || '%'
  )
JOIN 
  TopPosts AS tp ON tu.Id = tp.Id
ORDER BY 
  tu.TotalScore DESC;
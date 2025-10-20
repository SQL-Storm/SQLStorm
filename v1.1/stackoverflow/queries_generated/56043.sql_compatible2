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
    Posts p ON (
      -- emulate splitting '<tag1><tag2>' by looking for '<TagName>' pattern
      p.Tags IS NOT NULL
      AND POSITION('<' || t.TagName || '>' IN p.Tags) > 0
    )
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
    p.FavoriteCount,
    p.OwnerUserId
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
  TopTags tt ON EXISTS (
    SELECT 1
    FROM Posts p2
    WHERE p2.OwnerUserId = tu.Id
      AND p2.PostTypeId = 1
      AND p2.Tags IS NOT NULL
      AND POSITION('<' || tt.TagName || '>' IN p2.Tags) > 0
  )
JOIN 
  TopPosts tp ON tu.Id = tp.OwnerUserId
GROUP BY
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
ORDER BY 
  tu.TotalScore DESC;
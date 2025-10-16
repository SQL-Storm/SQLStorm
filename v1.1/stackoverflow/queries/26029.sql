WITH TopUsers AS (
  SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS PostCount,
    SUM(p.Score) AS TotalScore
  FROM 
    Users u
  JOIN 
    Posts p ON u.Id = p.OwnerUserId
  WHERE 
    p.PostTypeId = 1 AND p.Score > 0
  GROUP BY 
    u.Id, u.DisplayName, u.Reputation
  HAVING 
    COUNT(DISTINCT p.Id) > 10 AND SUM(p.Score) > 100
),
TopTags AS (
  SELECT 
    t.TagName,
    COUNT(DISTINCT p.Id) AS PostCount,
    SUM(p.Score) AS TotalScore
  FROM 
    Posts p
  JOIN 
    Tags t ON p.Tags LIKE '%' || t.TagName || '%'
  WHERE 
    p.PostTypeId = 1 AND p.Score > 0
  GROUP BY 
    t.TagName
  HAVING 
    COUNT(DISTINCT p.Id) > 10 AND SUM(p.Score) > 100
),
QuestionHistory AS (
  SELECT 
    p.Id,
    ph.PostHistoryTypeId,
    ph.CreationDate,
    ph.UserId,
    ph.UserDisplayName,
    ph.Comment
  FROM 
    Posts p
  JOIN 
    PostHistory ph ON p.Id = ph.PostId
  WHERE 
    ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20, 35)
)
SELECT 
  tu.DisplayName,
  tu.Reputation,
  tt.TagName,
  qh.PostHistoryTypeId,
  qh.CreationDate,
  qh.UserId,
  qh.UserDisplayName,
  qh.Comment,
  p.Score,
  p.ViewCount,
  p.AnswerCount,
  p.CommentCount,
  p.FavoriteCount,
  p.ClosedDate,
  p.CommunityOwnedDate,
  ROW_NUMBER() OVER (PARTITION BY tu.Id ORDER BY p.Score DESC) AS RowNum,
  tu.Id,
  tt.PostCount,
  tt.TotalScore,
  tu.PostCount,
  tu.TotalScore
FROM 
  TopUsers tu
JOIN 
  Posts p ON tu.Id = p.OwnerUserId
JOIN 
  TopTags tt ON p.Tags LIKE '%' || tt.TagName || '%'
LEFT JOIN 
  QuestionHistory qh ON p.Id = qh.Id
WHERE 
  p.PostTypeId = 1 AND p.Score > 0 AND p.ViewCount > 100
GROUP BY
  tu.DisplayName,
  tu.Reputation,
  tt.TagName,
  qh.PostHistoryTypeId,
  qh.CreationDate,
  qh.UserId,
  qh.UserDisplayName,
  qh.Comment,
  p.Score,
  p.ViewCount,
  p.AnswerCount,
  p.CommentCount,
  p.FavoriteCount,
  p.ClosedDate,
  p.CommunityOwnedDate,
  tu.Id,
  tt.PostCount,
  tt.TotalScore,
  tu.PostCount,
  tu.TotalScore
ORDER BY 
  tu.Reputation DESC, tt.PostCount DESC, p.Score DESC;
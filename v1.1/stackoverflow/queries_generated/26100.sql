-- {"query": "26100.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 627} 

WITH TopQuestions AS (
  SELECT 
    p.Id,
    p.Title,
    p.Score,
    p.ViewCount,
    p.Tags,
    ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS RowNum
  FROM 
    Posts p
  WHERE 
    p.PostTypeId = 1 AND p.ClosedDate IS NULL
),
TopUsers AS (
  SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT b.Id) AS BadgeCount,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, COUNT(DISTINCT b.Id) DESC) AS RowNum
  FROM 
    Users u
  LEFT JOIN 
    Badges b ON u.Id = b.UserId
  GROUP BY 
    u.Id, u.DisplayName, u.Reputation
),
QuestionComments AS (
  SELECT 
    p.Id,
    COUNT(c.Id) AS CommentCount,
    SUM(CASE WHEN c.Score > 0 THEN 1 ELSE 0 END) AS PositiveCommentCount,
    SUM(CASE WHEN c.Score < 0 THEN 1 ELSE 0 END) AS NegativeCommentCount
  FROM 
    Posts p
  LEFT JOIN 
    Comments c ON p.Id = c.PostId
  WHERE 
    p.PostTypeId = 1
  GROUP BY 
    p.Id
),
PostHistoryStats AS (
  SELECT 
    p.Id,
    COUNT(ph.Id) AS EditCount,
    SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseCount,
    SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenCount
  FROM 
    Posts p
  LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
  GROUP BY 
    p.Id
)
SELECT 
  p.Id,
  p.Title,
  p.Score,
  p.ViewCount,
  p.Tags,
  u.DisplayName AS OwnerDisplayName,
  u.Reputation AS OwnerReputation,
  b.Name AS BadgeName,
  ph.EditCount,
  ph.CloseCount,
  ph.ReopenCount,
  qc.CommentCount,
  qc.PositiveCommentCount,
  qc.NegativeCommentCount,
  ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS OverallRank
FROM 
  Posts p
JOIN 
  TopQuestions tq ON p.Id = tq.Id
JOIN 
  Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
  Badges b ON u.Id = b.UserId
JOIN 
  PostHistoryStats ph ON p.Id = ph.Id
JOIN 
  QuestionComments qc ON p.Id = qc.Id
WHERE 
  p.PostTypeId = 1 AND p.ClosedDate IS NULL
  AND u.Id IN (SELECT Id FROM TopUsers WHERE RowNum <= 10)
  AND p.Id IN (SELECT RelatedPostId FROM PostLinks WHERE LinkTypeId = 3)
ORDER BY 
  p.Score DESC, p.ViewCount DESC;

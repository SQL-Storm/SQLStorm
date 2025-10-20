WITH TopUsers AS (
  SELECT 
    u.Id, 
    u.DisplayName, 
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes, 
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
  FROM 
    Users u
  JOIN 
    Posts p ON u.Id = p.OwnerUserId
  JOIN 
    Votes v ON p.Id = v.PostId
  GROUP BY 
    u.Id, u.DisplayName
  HAVING 
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) > 1000
),
TopTags AS (
  SELECT 
    t.TagName, 
    COUNT(DISTINCT p.Id) AS PostCount
  FROM 
    Posts p
  JOIN 
    Tags t ON p.Tags LIKE '%' || t.TagName || '%'
  GROUP BY 
    t.TagName
  HAVING 
    COUNT(DISTINCT p.Id) > 500
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
    p.OwnerUserId,
    p.Tags
  FROM 
    Posts p
  JOIN 
    TopUsers u ON p.OwnerUserId = u.Id
  JOIN 
    TopTags t ON p.Tags LIKE '%' || t.TagName || '%'
  WHERE 
    p.PostTypeId = 1 AND p.Score > 100 AND p.ViewCount > 10000
)
SELECT 
  p.Id, 
  p.Title, 
  p.Score, 
  p.ViewCount, 
  p.AnswerCount, 
  p.CommentCount, 
  p.FavoriteCount, 
  u.DisplayName AS Owner, 
  t.TagName AS TopTag
FROM 
  TopPosts p
JOIN 
  TopUsers u ON p.OwnerUserId = u.Id
JOIN 
  TopTags t ON p.Tags LIKE '%' || t.TagName || '%'
ORDER BY 
  p.Score DESC, 
  p.ViewCount DESC;
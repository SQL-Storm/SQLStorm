-- {"query": "26083.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 662} 

WITH RankedPosts AS (
  SELECT 
    p.Id, 
    p.Score, 
    p.ViewCount, 
    p.Tags, 
    p.CreationDate, 
    p.LastActivityDate, 
    ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS ScoreRank,
    ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC) AS ViewCountRank
  FROM 
    Posts p
  WHERE 
    p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL
),
Top100Posts AS (
  SELECT 
    Id, 
    Score, 
    ViewCount, 
    Tags, 
    CreationDate, 
    LastActivityDate
  FROM 
    RankedPosts
  WHERE 
    ScoreRank <= 100 OR ViewCountRank <= 100
),
PostsWithUserBadges AS (
  SELECT 
    p.Id, 
    p.Score, 
    p.ViewCount, 
    p.Tags, 
    p.CreationDate, 
    p.LastActivityDate, 
    u.Id AS UserId, 
    u.DisplayName, 
    u.Reputation, 
    u.EmailHash, 
    b.Name AS BadgeName, 
    b.Date AS BadgeDate
  FROM 
    Top100Posts p
  JOIN 
    Users u ON p.OwnerUserId = u.Id
  LEFT JOIN 
    Badges b ON u.Id = b.UserId
),
PostsLinkedToOthers AS (
  SELECT 
    pl.PostId, 
    pl.RelatedPostId, 
    lt.Name AS LinkType
  FROM 
    PostLinks pl
  JOIN 
    LinkTypes lt ON pl.LinkTypeId = lt.Id
  WHERE 
    pl.PostId IN (SELECT Id FROM Top100Posts)
),
CommentsOnTopPosts AS (
  SELECT 
    c.Id, 
    c.PostId, 
    c.Score, 
    c.Text, 
    c.CreationDate, 
    c.UserDisplayName, 
    c.UserId
  FROM 
    Comments c
  WHERE 
    c.PostId IN (SELECT Id FROM Top100Posts)
)
SELECT 
  p.Id, 
  p.Score, 
  p.ViewCount, 
  p.Tags, 
  p.CreationDate, 
  p.LastActivityDate, 
  u.UserId, 
  u.DisplayName, 
  u.Reputation, 
  u.EmailHash, 
  b.BadgeName, 
  b.BadgeDate, 
  pl.RelatedPostId, 
  pl.LinkType, 
  c.Score AS CommentScore, 
  c.Text AS CommentText
FROM 
  PostsWithUserBadges p
LEFT JOIN 
  PostsLinkedToOthers pl ON p.Id = pl.PostId
LEFT JOIN 
  CommentsOnTopPosts c ON p.Id = c.PostId
WHERE 
  p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1)
  AND p.ViewCount > (SELECT AVG(ViewCount) FROM Posts WHERE PostTypeId = 1)
  AND p.Tags LIKE '%<java>%'
  AND p.CreationDate > NOW() - INTERVAL '1 year'
ORDER BY 
  p.Score DESC, 
  p.ViewCount DESC;

-- {"query": "26050.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 540} 

WITH RankedPosts AS (
  SELECT 
    p.Id,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.CreationDate,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS RowNum
  FROM 
    Posts p
  WHERE 
    p.PostTypeId IN (1, 2)
    AND p.Score > 0
),
TopPosts AS (
  SELECT 
    Id,
    Score,
    ViewCount,
    OwnerUserId,
    CreationDate
  FROM 
    RankedPosts
  WHERE 
    RowNum <= 10
),
UserBadges AS (
  SELECT 
    u.Id,
    COUNT(b.Id) AS BadgeCount
  FROM 
    Users u
  LEFT JOIN 
    Badges b ON u.Id = b.UserId
  GROUP BY 
    u.Id
),
PostHistoryDetails AS (
  SELECT 
    ph.PostId,
    COUNT(ph.Id) AS EditCount,
    MAX(ph.CreationDate) AS LastEditDate
  FROM 
    PostHistory ph
  WHERE 
    ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9)
  GROUP BY 
    ph.PostId
)
SELECT 
  p.Id,
  p.Title,
  p.Score,
  p.ViewCount,
  p.CreationDate,
  u.DisplayName AS OwnerDisplayName,
  u.Reputation AS OwnerReputation,
  ub.BadgeCount AS OwnerBadgeCount,
  phd.EditCount,
  phd.LastEditDate,
  COUNT(DISTINCT t.TagName) AS TagCount,
  SUM(v.VoteTypeId = 2) AS UpvoteCount,
  SUM(v.VoteTypeId = 3) AS DownvoteCount
FROM 
  Posts p
JOIN 
  TopPosts tp ON p.Id = tp.Id
JOIN 
  Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
  UserBadges ub ON u.Id = ub.Id
LEFT JOIN 
  PostHistoryDetails phd ON p.Id = phd.PostId
LEFT JOIN 
  PostTags pt ON p.Id = pt.PostId
LEFT JOIN 
  Tags t ON pt.TagId = t.Id
LEFT JOIN 
  Votes v ON p.Id = v.PostId
GROUP BY 
  p.Id,
  p.Title,
  p.Score,
  p.ViewCount,
  p.CreationDate,
  u.DisplayName,
  u.Reputation,
  ub.BadgeCount,
  phd.EditCount,
  phd.LastEditDate
ORDER BY 
  p.Score DESC;

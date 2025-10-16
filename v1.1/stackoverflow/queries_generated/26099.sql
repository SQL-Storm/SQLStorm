-- {"query": "26099.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 654} 

WITH RankedPosts AS (
  SELECT 
    p.Id,
    p.PostTypeId,
    p.Score,
    p.ViewCount,
    p.Tags,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS RowNum
  FROM 
    Posts p
  WHERE 
    p.PostTypeId IN (1, 2)
),
TopPosts AS (
  SELECT 
    rp.Id,
    rp.PostTypeId,
    rp.Score,
    rp.ViewCount,
    rp.Tags,
    rp.RowNum
  FROM 
    RankedPosts rp
  WHERE 
    rp.RowNum <= 10
),
UserReputation AS (
  SELECT 
    u.Id,
    u.Reputation,
    COUNT(b.Id) AS BadgeCount
  FROM 
    Users u
  LEFT JOIN 
    Badges b ON u.Id = b.UserId
  GROUP BY 
    u.Id, u.Reputation
),
PostHistoryStats AS (
  SELECT 
    ph.PostId,
    COUNT(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 END) AS ClosedCount,
    COUNT(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 END) AS ReopenedCount,
    COUNT(CASE WHEN ph.PostHistoryTypeId = 12 THEN 1 END) AS DeletedCount,
    COUNT(CASE WHEN ph.PostHistoryTypeId = 13 THEN 1 END) AS UndeletedCount
  FROM 
    PostHistory ph
  GROUP BY 
    ph.PostId
)
SELECT 
  p.Id,
  p.PostTypeId,
  p.Score,
  p.ViewCount,
  p.Tags,
  COALESCE(urs.Reputation, 0) AS UserReputation,
  COALESCE(urs.BadgeCount, 0) AS UserBadgeCount,
  COALESCE(phs.ClosedCount, 0) AS ClosedCount,
  COALESCE(phs.ReopenedCount, 0) AS ReopenedCount,
  COALESCE(phs.DeletedCount, 0) AS DeletedCount,
  COALESCE(phs.UndeletedCount, 0) AS UndeletedCount,
  v.VoteTypeId,
  COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVoteCount,
  COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVoteCount
FROM 
  Posts p
LEFT JOIN 
  Users u ON p.OwnerUserId = u.Id
LEFT JOIN 
  UserReputation urs ON u.Id = urs.Id
LEFT JOIN 
  PostHistoryStats phs ON p.Id = phs.PostId
LEFT JOIN 
  Votes v ON p.Id = v.PostId
WHERE 
  p.Id IN (SELECT Id FROM TopPosts)
GROUP BY 
  p.Id,
  p.PostTypeId,
  p.Score,
  p.ViewCount,
  p.Tags,
  urs.Reputation,
  urs.BadgeCount,
  phs.ClosedCount,
  phs.ReopenedCount,
  phs.DeletedCount,
  phs.UndeletedCount,
  v.VoteTypeId
ORDER BY 
  p.Score DESC;

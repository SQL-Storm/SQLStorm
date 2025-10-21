-- {"query": "26026.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 686} 
WITH TopPosts AS (
  SELECT 
    p.Id,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    ROW_NUMBER() OVER (PARTITION BY p.Tags ORDER BY p.Score DESC) AS RowNum
  FROM 
    Posts p
  WHERE 
    p.PostTypeId = 1
),
TopUsers AS (
  SELECT 
    u.Id,
    u.Reputation,
    u.DisplayName,
    COUNT(DISTINCT b.Id) AS BadgeCount,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
  FROM 
    Users u
  LEFT JOIN 
    Badges b ON u.Id = b.UserId
  GROUP BY 
    u.Id, u.Reputation, u.DisplayName
),
PostHistoryStats AS (
  SELECT 
    ph.PostId,
    COUNT(DISTINCT ph.PostHistoryTypeId) AS HistoryCount,
    MAX(ph.CreationDate) AS LastHistoryDate
  FROM 
    PostHistory ph
  GROUP BY 
    ph.PostId
),
VoteStats AS (
  SELECT 
    v.PostId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
  FROM 
    Votes v
  GROUP BY 
    v.PostId
)
SELECT 
  p.Id,
  p.Title,
  p.Score,
  p.ViewCount,
  p.Tags,
  p.CreationDate,
  p.LastActivityDate,
  COALESCE(phs.HistoryCount, 0) AS HistoryCount,
  COALESCE(phs.LastHistoryDate, '1900-01-01') AS LastHistoryDate,
  COALESCE(vs.UpVotes, 0) AS UpVotes,
  COALESCE(vs.DownVotes, 0) AS DownVotes,
  tu.Reputation,
  tu.DisplayName,
  tu.BadgeCount,
  tu.GoldBadges,
  tu.SilverBadges,
  tu.BronzeBadges,
  CASE 
    WHEN p.Score > 10 AND p.ViewCount > 1000 THEN 'HighScoreHighView'
    WHEN p.Score > 10 AND p.ViewCount <= 1000 THEN 'HighScoreLowView'
    WHEN p.Score <= 10 AND p.ViewCount > 1000 THEN 'LowScoreHighView'
    ELSE 'LowScoreLowView'
  END AS PostCategory,
  ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS RowNum
FROM 
  Posts p
LEFT JOIN 
  PostHistoryStats phs ON p.Id = phs.PostId
LEFT JOIN 
  VoteStats vs ON p.Id = vs.PostId
LEFT JOIN 
  TopUsers tu ON p.OwnerUserId = tu.Id
WHERE 
  p.PostTypeId = 1
  AND p.Id IN (SELECT Id FROM TopPosts WHERE RowNum <= 10)
ORDER BY 
  p.Score DESC;
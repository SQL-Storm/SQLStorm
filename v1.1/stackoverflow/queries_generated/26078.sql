-- {"query": "26078.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 883} 

WITH RankedPosts AS (
  SELECT 
    p.Id,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.FavoriteCount,
    ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS ScoreRank,
    ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC) AS ViewRank,
    ROW_NUMBER() OVER (ORDER BY p.CommentCount DESC) AS CommentRank,
    ROW_NUMBER() OVER (ORDER BY p.FavoriteCount DESC) AS FavoriteRank
  FROM 
    Posts p
),
UserBadges AS (
  SELECT 
    u.Id,
    COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
    COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
    COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
  FROM 
    Users u
  LEFT JOIN 
    Badges b ON u.Id = b.UserId
  GROUP BY 
    u.Id
),
PostVotes AS (
  SELECT 
    p.Id,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
  FROM 
    Posts p
  LEFT JOIN 
    Votes v ON p.Id = v.PostId
  GROUP BY 
    p.Id
),
PostHistoryStats AS (
  SELECT 
    p.Id,
    COUNT(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 END) AS CloseCount,
    COUNT(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 END) AS ReopenCount,
    COUNT(CASE WHEN ph.PostHistoryTypeId = 12 THEN 1 END) AS DeleteCount,
    COUNT(CASE WHEN ph.PostHistoryTypeId = 13 THEN 1 END) AS UndeleteCount
  FROM 
    Posts p
  LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
  GROUP BY 
    p.Id
)
SELECT 
  p.Id,
  p.Score,
  p.ViewCount,
  p.CommentCount,
  p.FavoriteCount,
  rp.ScoreRank,
  rp.ViewRank,
  rp.CommentRank,
  rp.FavoriteRank,
  ub.GoldBadges,
  ub.SilverBadges,
  ub.BronzeBadges,
  pv.UpVotes,
  pv.DownVotes,
  phs.CloseCount,
  phs.ReopenCount,
  phs.DeleteCount,
  phs.UndeleteCount,
  CASE 
    WHEN p.Score > 100 AND p.ViewCount > 1000 THEN 'HighScoreHighView'
    WHEN p.Score > 100 AND p.ViewCount <= 1000 THEN 'HighScoreLowView'
    WHEN p.Score <= 100 AND p.ViewCount > 1000 THEN 'LowScoreHighView'
    ELSE 'LowScoreLowView'
  END AS PostCategory,
  CASE 
    WHEN ub.GoldBadges > 10 THEN 'HighGold'
    WHEN ub.GoldBadges <= 10 AND ub.SilverBadges > 10 THEN 'HighSilver'
    ELSE 'LowBadges'
  END AS UserBadgeCategory
FROM 
  Posts p
JOIN 
  RankedPosts rp ON p.Id = rp.Id
JOIN 
  UserBadges ub ON p.OwnerUserId = ub.Id
JOIN 
  PostVotes pv ON p.Id = pv.Id
JOIN 
  PostHistoryStats phs ON p.Id = phs.Id
WHERE 
  p.Score > 0 AND p.ViewCount > 0 AND p.CommentCount > 0 AND p.FavoriteCount > 0
  AND ub.GoldBadges > 0 AND ub.SilverBadges > 0 AND ub.BronzeBadges > 0
  AND pv.UpVotes > 0 AND pv.DownVotes > 0
  AND phs.CloseCount > 0 AND phs.ReopenCount > 0 AND phs.DeleteCount > 0 AND phs.UndeleteCount > 0
ORDER BY 
  p.Score DESC, p.ViewCount DESC, p.CommentCount DESC, p.FavoriteCount DESC;

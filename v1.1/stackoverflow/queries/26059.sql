-- {"query": "26059.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 532} 
WITH RankedPosts AS (
  SELECT 
    p.Id, 
    p.PostTypeId, 
    p.Score, 
    p.ViewCount, 
    p.Title, 
    p.Tags, 
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS ScoreRank,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.ViewCount DESC) AS ViewRank
  FROM Posts p
),
TopPosts AS (
  SELECT 
    rp.Id, 
    rp.PostTypeId, 
    rp.Score, 
    rp.ViewCount, 
    rp.Title, 
    rp.Tags, 
    rp.ScoreRank, 
    rp.ViewRank
  FROM RankedPosts rp
  WHERE rp.ScoreRank <= 10 OR rp.ViewRank <= 10
),
UserBadges AS (
  SELECT 
    u.Id, 
    COUNT(b.Id) AS BadgeCount
  FROM Users u
  LEFT JOIN Badges b ON u.Id = b.UserId
  GROUP BY u.Id
),
PostVotes AS (
  SELECT 
    p.Id, 
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
  FROM Posts p
  LEFT JOIN Votes v ON p.Id = v.PostId
  GROUP BY p.Id
)
SELECT 
  p.Id, 
  p.PostTypeId, 
  p.Score, 
  p.ViewCount, 
  p.Title, 
  p.Tags, 
  tp.ScoreRank, 
  tp.ViewRank, 
  ub.BadgeCount, 
  pv.UpVotes, 
  pv.DownVotes,
  u.Reputation, 
  u.CreationDate, 
  u.LastAccessDate
FROM Posts p
JOIN TopPosts tp ON p.Id = tp.Id
LEFT JOIN UserBadges ub ON p.OwnerUserId = ub.Id
LEFT JOIN PostVotes pv ON p.Id = pv.Id
LEFT JOIN Users u ON p.OwnerUserId = u.Id
WHERE p.PostTypeId = 1 AND p.Score > 10
AND EXISTS (
  SELECT 1
  FROM PostHistory ph
  WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 10
  AND ph.Comment LIKE '%Off-topic%'
)
OR p.Id IN (
  SELECT pl.RelatedPostId
  FROM PostLinks pl
  WHERE pl.LinkTypeId = 3
)
ORDER BY p.Score DESC, p.ViewCount DESC;
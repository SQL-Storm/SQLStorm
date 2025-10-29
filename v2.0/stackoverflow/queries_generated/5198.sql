-- {"query": "5198.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 541} 
WITH RecentHot AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    u.DisplayName AS OwnerName,
    p.CommentCount,
    p.FavoriteCount,
    p.LastActivityDate,
    ROW_NUMBER() OVER (ORDER BY p.LastActivityDate DESC, p.Score DESC) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
    AND p.ClosedDate IS NULL
),
Agg AS (
  SELECT
    h.PostId,
    h.CreationDate AS HistoryDate,
    h.UserId AS ActionUserId,
    vu.DisplayName AS ActionUserName,
    h.Comment AS Note,
    h.PostHistoryTypeId
  FROM PostHistory h
  LEFT JOIN Users vu ON h.UserId = vu.Id
  WHERE h.PostHistoryTypeId IN (10, 16, 22) -- close, community owned, unmerged
),
Joined AS (
  SELECT
    rh.PostId,
    rh.Title,
    rh.Tags,
    rh.CreationDate AS PostCreated,
    rh.LastActivityDate,
    rh.ViewCount,
    rh.Score,
    rh.OwnerUserId,
    rh.OwnerName,
    rh.CommentCount,
    rh.FavoriteCount,
    a.HistoryDate,
    a.ActionUserName,
    a.Note,
    a.PostHistoryTypeId
  FROM RecentHot rh
  LEFT JOIN Agg a ON rh.PostId = a.PostId
)
SELECT
  j.PostId,
  j.Title,
  j.Tags,
  j.PostCreated,
  j.LastActivityDate,
  j.ViewCount,
  j.Score,
  j.OwnerUserId,
  j.OwnerName,
  j.CommentCount,
  j.FavoriteCount,
  j.HistoryDate,
  j.ActionUserName,
  j.Note,
  j.PostHistoryTypeId,
  CASE
    WHEN j.Score > 0 AND j.ViewCount > 1000 THEN 'Hot'
    WHEN j.Score <= 0 AND j.ViewCount > 2000 THEN 'Trending'
    ELSE 'Stable'
  END AS StatusBucket,
  (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = j.PostId AND v.VoteTypeId = 9) AS AvgBountyClose
FROM Joined j
ORDER BY
  j.LastActivityDate DESC,
  j.Score DESC,
  j.ViewCount DESC
LIMIT 100;
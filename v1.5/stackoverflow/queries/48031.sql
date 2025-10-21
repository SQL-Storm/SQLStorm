WITH RankedPosts AS (
  SELECT
    p.Id,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) as rn
  FROM Posts p
  WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL AND p.AcceptedAnswerId IS NOT NULL
),
UserActivity AS (
  SELECT
    u.Id AS UserId,
    COUNT(DISTINCT ph.PostId) AS PostHistoryCount,
    AVG(EXTRACT(EPOCH FROM (u.LastAccessDate - ph.CreationDate)) / 60.0) AS AvgMinutesSinceLastAccess
  FROM Users u
  JOIN PostHistory ph ON u.Id = ph.UserId
  GROUP BY u.Id
),
PostMetrics AS (
  SELECT
    rp.Id AS PostId,
    rp.OwnerUserId,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    ua.PostHistoryCount,
    ua.AvgMinutesSinceLastAccess,
    ROW_NUMBER() OVER (ORDER BY rp.Score DESC, rp.ViewCount DESC) AS ScoreViewRank,
    ROW_NUMBER() OVER (ORDER BY rp.AnswerCount DESC) AS AnswerRank,
    ROW_NUMBER() OVER (ORDER BY rp.FavoriteCount DESC) AS FavoriteRank,
    ROW_NUMBER() OVER (ORDER BY ua.PostHistoryCount DESC) AS HistoryRank,
    ROW_NUMBER() OVER (ORDER BY ua.AvgMinutesSinceLastAccess ASC) AS AvgAccessRank
  FROM RankedPosts rp
  LEFT JOIN UserActivity ua ON rp.OwnerUserId = ua.UserId
  WHERE rp.rn <= 1000
)
SELECT
  pm.PostId,
  pm.OwnerUserId,
  pm.CreationDate,
  pm.Score,
  pm.ViewCount,
  pm.AnswerCount,
  pm.CommentCount,
  pm.FavoriteCount,
  pm.PostHistoryCount,
  pm.AvgMinutesSinceLastAccess,
  (
    pm.ScoreViewRank + pm.AnswerRank + pm.FavoriteRank + pm.HistoryRank + pm.AvgAccessRank
  ) AS CompositeRank
FROM PostMetrics pm
ORDER BY CompositeRank
LIMIT 50;
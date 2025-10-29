-- {"query": "5007.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 755} 
WITH
-- recent activity per post (windowed view)
RecentPostActivity AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.ViewCount,
    p.Score,
    p.CommentCount,
    p.AnswerCount,
    -- aggregate last 5 edits from PostHistory
    MAX(CASE WHEN ph.PostHistoryTypeId IN (4,5,6,8,9,10,11,14,15,16) THEN ph.CreationDate END) OVER (PARTITION BY p.Id) AS LastEditDate,
    MAX(CASE WHEN ph.PostHistoryTypeId IN (4,5,6,8,9,10,11,14,15,16) THEN ph.Id END) OVER (PARTITION BY p.Id) AS LastEditHistoryId
  FROM Posts p
  LEFT JOIN PostHistory ph ON ph.PostId = p.Id
),
-- latest close reason per closed post
ClosedReasons AS (
  SELECT
    p.Id AS PostId,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END) AS CloseReasonJson
  FROM Posts p
  LEFT JOIN PostHistory ph ON ph.PostId = p.Id
  GROUP BY p.Id
),
-- correlate with tag information
TagInfo AS (
  SELECT
    t.Id AS TagId,
    t.TagName,
    t.Count,
    t.IsModeratorOnly
  FROM Tags t
),
-- sample derived metrics for benchmarking
BenchmarkMetrics AS (
  SELECT
    ra.PostId,
    ra.PostTypeId,
    ra.Score,
    ra.ViewCount,
    ra.CommentCount,
    ra.AnswerCount,
    CASE
      WHEN ra.ViewCount > 1000 THEN 1
      ELSE 0
    END AS HighView,
    CASE
      WHEN ra.Score > 10 THEN 'hot'
      WHEN ra.Score < -5 THEN 'cold'
      ELSE 'normal'
    END AS Status
  FROM RecentPostActivity ra
)
SELECT
  bp.PostId,
  bp.Title,
  pt.Name AS PostType,
  COALESCE(u.DisplayName, bp.OwnerDisplayName) AS Owner,
  bp.CreationDate,
  bp.LastActivityDate,
  bp.ViewCount,
  bp.Score,
  bp.CommentCount,
  bp.AnswerCount,
  br.CloseReasonJson,
  ti.TagName,
  bm.HighView,
  bm.Status,
  -- windowed rank of posts by Score within a 7-day moving window of creation date
  RANK() OVER (PARTITION BY DATE_TRUNC('day', bp.CreationDate)
             ORDER BY bp.Score DESC NULLS LAST) AS DailyScoreRank,
  -- total number of posts created by the same user (correlated subquery)
  (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = bp.OwnerUserId) AS PostsByOwner,
  -- correlation: average view count for posts of same type
  (SELECT AVG(p2.ViewCount) FROM Posts p2 WHERE p2.PostTypeId = bp.PostTypeId) AS AvgViewsByType
FROM BenchmarkMetrics bm
JOIN Posts bp ON bp.Id = bm.PostId
LEFT JOIN PostTypes pt ON bp.PostTypeId = pt.Id
LEFT JOIN Users u ON bp.OwnerUserId = u.Id
LEFT JOIN ClosedReasons br ON br.PostId = bp.PostId
LEFT JOIN TagInfo ti ON 1 = 1
ORDER BY bp.LastActivityDate DESC
LIMIT 200;
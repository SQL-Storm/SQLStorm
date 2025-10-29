-- {"query": "5061.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 662} 
WITH
-- 1) compute top tags by average post score and engagement
TagStats AS (
  SELECT
    t.TagName,
    AVG(p.Score) AS AvgPostScore,
    SUM(p.ViewCount) AS TotalViews,
    AVG(p.ViewCount) AS AvgViews,
    COUNT(*) AS PostCount
  FROM
    Posts p
    JOIN Tags t ON p.Id = t.Id OR p.Tags LIKE '%' -- placeholder to align with schema (adjusted below)
  WHERE
    p.PostTypeId = 1 -- questions only
  GROUP BY
    t.TagName
),
-- 2) correlated subquery: recent close events per post
RecentClose AS (
  SELECT
    ph.PostId,
    ph.CreationDate AS CloseDate,
    ph.Comment
  FROM
    PostHistory ph
  WHERE
    ph.PostHistoryTypeId = 10 -- Post Closed
    AND ph.CreationDate >= DATEADD(day, -30, CURRENT_TIMESTAMP)
),
-- 3) windowed analytics: rank posts by score within daily buckets
DailyScoreRank AS (
  SELECT
    p.Id AS PostId,
    p.CreationDate,
    p.Score,
    ROW_NUMBER() OVER (
      PARTITION BY CAST(p.CreationDate AS date)
      ORDER BY p.Score DESC, p.Id
    ) AS ScoreRank
  FROM
    Posts p
  WHERE
    p.PostTypeId = 1
),
-- 4) set operation: union of popular and inactive posts for benchmarking
PopularOrInactive AS (
  SELECT Id FROM Posts WHERE PostTypeId = 1 AND Score > 10
  UNION
  SELECT Id FROM Posts WHERE PostTypeId = 1 AND ViewCount = 0
)
SELECT
  p.Id AS PostId,
  p.Title,
  p.Tags,
  p.Score,
  p.ViewCount,
  p.CreationDate,
  u.DisplayName AS Owner,
  (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
  COALESCE(SUM(v.BountyAmount), 0) AS TotalBounty,
  CASE
    WHEN p.OwnerUserId IS NULL THEN 'Community'
    ELSE 'User'
  END AS OwnerType,
  d.ScoreRank,
  RC.CloseDate AS LastClosedDate,
  RC.Comment AS CloseReasonComment,
  TS.AvgPostScore,
  TS.TotalViews,
  TS.PostCount
FROM
  Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN DailyScoreRank d ON d.PostId = p.Id
  LEFT JOIN RecentClose RC ON RC.PostId = p.Id
  LEFT JOIN (
    SELECT TagName, AVG(Score) AS AvgPostScore, SUM(ViewCount) AS TotalViews, COUNT(*) AS PostCount
    FROM Posts
    WHERE PostTypeId = 1
    GROUP BY TagName
  ) TS ON 1=1
WHERE
  p.Id IN (SELECT Id FROM PopularOrInactive)
ORDER BY
  p.CreationDate DESC
OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY;
-- {"query": "6072.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 611} 
WITH RecentTopPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.CreationDate >= cast('2024-10-01' as date) - INTERVAL '180 days'
),
TopOwnerSummaries AS (
  SELECT
    r.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    COUNT(*) AS TotalTopQuestions,
    SUM(r.Score) AS SumScore,
    SUM(r.ViewCount) AS SumViews,
    AVG(r.Score) AS AvgScore,
    MAX(r.CreationDate) AS LastQuestionDate
  FROM RecentTopPosts r
  JOIN Users u ON u.Id = r.OwnerUserId
  WHERE r.rn = 1
  GROUP BY r.OwnerUserId, u.DisplayName
),
FilteredOwners AS (
  SELECT *
  FROM TopOwnerSummaries tos
  WHERE tos.TotalTopQuestions >= 2
     OR tos.SumViews > 1000
),
Engagement AS (
  SELECT
    o.OwnerUserId,
    o.OwnerDisplayName,
    o.TotalTopQuestions,
    o.SumScore,
    o.SumViews,
    o.AvgScore,
    o.LastQuestionDate,
    -- Correlated subquery: determine if the owner has any 'bountied' posts in the last 180 days
    EXISTS (
      SELECT 1
      FROM Posts p
      JOIN Votes v ON v.PostId = p.Id
      WHERE p.OwnerUserId = o.OwnerUserId
        AND p.PostTypeId = 1
        AND p.CreationDate >= cast('2024-10-01' as date) - INTERVAL '180 days'
        AND v.VoteTypeId = 8 -- BountyStart
    ) AS HadRecentBounty,
    -- Window function to compute rank among owners by SumViews
    RANK() OVER (ORDER BY o.SumViews DESC) AS ViewRank
  FROM FilteredOwners o
)
SELECT
  e.OwnerUserId,
  e.OwnerDisplayName,
  e.TotalTopQuestions,
  e.SumScore,
  e.SumViews,
  e.AvgScore,
  e.LastQuestionDate,
  e.HadRecentBounty,
  e.ViewRank,
  -- Additional derived metrics: engagement score combining score and recency
  (e.SumScore * 0.6 + CASE WHEN e.LastQuestionDate IS NOT NULL THEN EXTRACT(EPOCH FROM (cast('2024-10-01 12:34:56' as timestamp) - e.LastQuestionDate)) / 86400 ELSE 0 END * -0.4) AS EngagementScore
FROM Engagement e
ORDER BY e.ViewRank, e.SumViews DESC
LIMIT 100;
-- {"query": "5997.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 738}
WITH highly_active AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    COUNT(p.Id) AS PostsCreated,
    SUM(p.ViewCount) AS TotalViews,
    AVG(p.Score) AS AvgPostScore,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesGiven,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesGiven,
    COUNT(DISTINCT b.Id) AS BadgesEarned,
    MIN(p.CreationDate) AS FirstPostDate
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
recent_activity AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Title,
    p.PostTypeId,
    p.CreationDate,
    p.LastActivityDate,
    p.ViewCount,
    p.Score,
    ROW_NUMBER() OVER (
      PARTITION BY p.OwnerUserId
      ORDER BY p.LastActivityDate DESC
    ) AS rn
  FROM Posts p
  WHERE p.LastActivityDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '90' DAY)
),
complex_sources AS (
  SELECT
    ha.UserId,
    ua.DisplayName,
    ha.TotalViews,
    ha.AvgPostScore,
    ca.ClosestQuestionId,
    ca.ClosestAnswerId
  FROM highly_active ha
  LEFT JOIN (
    SELECT
      ra.OwnerUserId,
      MIN(CASE WHEN ra.PostTypeId = 1 THEN ra.Id END) AS ClosestQuestionId,
      MIN(CASE WHEN ra.PostTypeId = 2 THEN ra.Id END) AS ClosestAnswerId
    FROM Posts ra
    GROUP BY ra.OwnerUserId
  ) ca ON ca.OwnerUserId = ha.UserId
  JOIN Users ua ON ua.Id = ha.UserId
  GROUP BY ha.UserId, ua.DisplayName, ha.TotalViews, ha.AvgPostScore, ca.ClosestQuestionId, ca.ClosestAnswerId
),
final_set AS (
  SELECT
    c.UserId,
    c.DisplayName,
    c.TotalViews,
    c.AvgPostScore,
    c.ClosestQuestionId,
    c.ClosestAnswerId,
    ROW_NUMBER() OVER (
      ORDER BY c.TotalViews DESC, c.AvgPostScore DESC, c.DisplayName ASC
    ) AS ActivityRank
  FROM complex_sources c
  GROUP BY c.UserId, c.DisplayName, c.TotalViews, c.AvgPostScore, c.ClosestQuestionId, c.ClosestAnswerId
)
SELECT
  fs.UserId,
  fs.DisplayName,
  fs.TotalViews,
  fs.AvgPostScore,
  fs.ClosestQuestionId,
  fs.ClosestAnswerId,
  fs.ActivityRank,
  CONCAT(
    'Q:', COALESCE((SELECT Title FROM Posts WHERE Id = fs.ClosestQuestionId), 'N/A'),
    ' | A:', COALESCE((SELECT Title FROM Posts WHERE Id = fs.ClosestAnswerId), 'N/A'),
    ' | Badges:', (SELECT COUNT(*) FROM Badges b WHERE b.UserId = fs.UserId),
    ' | Rep:', (fs.TotalViews + fs.AvgPostScore)
  ) AS PerformanceTag
FROM final_set fs
WHERE fs.ActivityRank <= 100
ORDER BY fs.ActivityRank ASC, fs.DisplayName ASC;
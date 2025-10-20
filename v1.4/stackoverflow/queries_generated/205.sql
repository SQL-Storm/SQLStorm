-- {"query": "205.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 11255} 
WITH
UserSummary AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COALESCE(u.Location, '') AS Location,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id) AS PostCount,
    (SELECT COALESCE(SUM(p.Score), 0) FROM Posts p WHERE p.OwnerUserId = u.Id) AS ScoreSum,
    (SELECT MAX(p.LastActivityDate) FROM Posts p WHERE p.OwnerUserId = u.Id) AS LastPostActivity
  FROM Users u
),
TopPosts AS (
  SELECT
    p.OwnerUserId AS UserId,
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.Tags,
    ROW_NUMBER() OVER (
      PARTITION BY p.OwnerUserId
      ORDER BY COALESCE(p.Score, 0) DESC NULLS LAST,
               COALESCE(p.ViewCount, 0) DESC NULLS LAST
    ) AS rn
  FROM Posts p
  WHERE p.PostTypeId IN (1, 2)
),
DistinctTagCount AS (
  SELECT
    tps.UserId,
    COUNT(DISTINCT l.tag) AS DistinctTagCount
  FROM TopPosts tps
  LEFT JOIN LATERAL (
     SELECT unnest(string_to_array(substring(tps.Tags, 2, length(tps.Tags) - 2), '><')) AS tag
  ) l ON true
  GROUP BY tps.UserId
)
SELECT
  'UserEngagement' AS Benchmark,
  us.UserId,
  us.DisplayName,
  us.Reputation,
  us.Location,
  us.PostCount,
  us.ScoreSum,
  COALESCE(dt.DistinctTagCount, 0) AS DistinctTagCount,
  us.LastPostActivity,
  (SELECT tp.PostId FROM TopPosts tp WHERE tp.UserId = us.UserId AND tp.rn = 1) AS TopPostId,
  (SELECT tp.Title  FROM TopPosts tp WHERE tp.UserId = us.UserId AND tp.rn = 1) AS TopPostTitle,
  (SELECT tp.Score  FROM TopPosts tp WHERE tp.UserId = us.UserId AND tp.rn = 1) AS TopPostScore
FROM UserSummary us
LEFT JOIN DistinctTagCount dt ON dt.UserId = us.UserId
UNION ALL
SELECT
  'TagDensity' AS Benchmark,
  us.UserId,
  us.DisplayName,
  us.Reputation,
  us.Location,
  us.PostCount,
  us.ScoreSum,
  COALESCE(dt.DistinctTagCount, 0) AS DistinctTagCount,
  us.LastPostActivity,
  NULL AS TopPostId,
  NULL AS TopPostTitle,
  NULL AS TopPostScore
FROM UserSummary us
LEFT JOIN DistinctTagCount dt ON dt.UserId = us.UserId
ORDER BY Benchmark, UserId;
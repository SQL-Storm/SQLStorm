-- {"query": "5555.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 903}
WITH
RecentActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    p.Id AS PostId,
    p.Title,
    p.PostTypeId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.CreationDate DESC) AS rn
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  WHERE p.CreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '180 days'
),
UserMetrics AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    (SELECT COUNT(*) FROM Posts p6 WHERE p6.OwnerUserId = u.Id AND p6.CreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '180 days') AS PostsLast6m,
    (SELECT COALESCE(SUM(p6.Score),0) FROM Posts p6 WHERE p6.OwnerUserId = u.Id AND p6.CreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '180 days') AS ScoreLast6m,
    (SELECT COALESCE(MAX(p6.ViewCount),0) FROM Posts p6 WHERE p6.OwnerUserId = u.Id) AS MaxViewsAllPosts,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id) AS BadgeCount,
    (SELECT COALESCE(SUM(v.BountyAmount),0)
       FROM Votes v
       JOIN Posts p ON p.Id = v.PostId
       WHERE p.OwnerUserId = u.Id AND v.VoteTypeId = 2) AS UpvotesReceived
  FROM Users u
  WHERE u.AccountId IS NOT NULL
),
HotQuestionScan AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.ViewCount,
    p.Score,
    p.CreationDate,
    p.LastActivityDate,
    (p.Score * 1.0 / NULLIF(p.ViewCount,0)) AS ScorePerView,
    ROW_NUMBER() OVER (ORDER BY (p.Score * 0.7 + p.ViewCount * 0.3) DESC) AS HotRank,
    p.Tags
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.ClosedDate IS NULL
    AND p.Tags IS NOT NULL
),
Composite AS (
  SELECT
    COALESCE(u.Id, um.UserId) AS UserId,
    COALESCE(u.DisplayName, um.DisplayName) AS DisplayName,
    mh.PostId,
    mh.Title,
    mh.ViewCount,
    mh.Score,
    mh.ScorePerView,
    mh.HotRank,
    um.PostsLast6m,
    um.ScoreLast6m,
    um.MaxViewsAllPosts,
    um.BadgeCount,
    CASE
      WHEN mh.Score > 0 THEN 'Positive'
      WHEN mh.Score < 0 THEN 'Negative'
      ELSE 'Neutral'
    END AS Sentiment,
    CASE
      WHEN mh.Tags LIKE '%<java>%' THEN true ELSE false
    END AS ContainsJavaTag
  FROM HotQuestionScan mh
  CROSS JOIN UserMetrics um
  LEFT JOIN Users u ON u.Id = (
    SELECT p2.OwnerUserId FROM Posts p2 WHERE p2.Id = mh.PostId
  )
  WHERE mh.HotRank <= 50
    AND mh.Score IS NOT NULL
)
SELECT
  c.UserId,
  c.DisplayName,
  c.PostId,
  c.Title,
  c.ViewCount,
  c.Score,
  c.ScorePerView,
  c.HotRank,
  c.PostsLast6m,
  c.ScoreLast6m,
  c.MaxViewsAllPosts,
  c.BadgeCount,
  c.Sentiment,
  c.ContainsJavaTag
FROM Composite c
ORDER BY c.HotRank, c.Score DESC
LIMIT 100;
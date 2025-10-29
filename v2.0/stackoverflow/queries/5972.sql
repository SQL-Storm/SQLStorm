WITH
RecentActivePosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.PostTypeId,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '180 days'
),
TagStats AS (
  SELECT
    tag AS TagName,
    COUNT(*) AS PostCount,
    AVG(p.Score) AS AvgScore,
    MAX(p.LastActivityDate) AS LastActive
  FROM Posts p
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(COALESCE(p.Tags, ''), '<>')) AS tag
  ) AS t
  GROUP BY tag
),
HighImpactUsers AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate
  FROM Users u
  WHERE u.Reputation > 10000
),
CrossJoined AS (
  SELECT
    p.PostId,
    p.Title,
    p.OwnerUserId,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    u.DisplayName AS OwnerDisplayName,
    v.VoteCount
  FROM RecentActivePosts p
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS VoteCount
    FROM Votes
    WHERE CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '60 days'
    GROUP BY PostId
  ) v ON v.PostId = p.PostId
  LEFT JOIN Users u ON u.Id = p.OwnerUserId
  WHERE p.rn = 1
),
Windowed AS (
  SELECT
    c.PostId,
    c.Title,
    c.OwnerUserId,
    c.LastActivityDate,
    c.Score,
    c.ViewCount,
    c.Tags,
    c.OwnerDisplayName,
    c.VoteCount,
    ROW_NUMBER() OVER (ORDER BY c.LastActivityDate DESC, c.Score DESC) AS seq
  FROM CrossJoined c
)
SELECT
  w.PostId,
  w.Title,
  w.OwnerDisplayName,
  w.LastActivityDate,
  w.Score,
  w.ViewCount,
  w.Tags,
  w.VoteCount,
  (SELECT COUNT(*) FROM HighImpactUsers hi WHERE hi.Reputation > 5000) AS RichUserBucketSize,
  (
    SELECT STRING_AGG(tg.tag, ', ' ORDER BY tg.tag)
    FROM (
      SELECT unnest(string_to_array(COALESCE(w.Tags, ''), '<>')) AS tag
    ) AS tg
  ) AS TagList
FROM Windowed w
LEFT JOIN TagStats ts ON true
LEFT JOIN HighImpactUsers hui ON hui.UserId = w.OwnerUserId
WHERE w.seq = 1
GROUP BY
  w.PostId,
  w.Title,
  w.OwnerDisplayName,
  w.LastActivityDate,
  w.Score,
  w.ViewCount,
  w.Tags,
  w.VoteCount,
  w.seq
ORDER BY w.LastActivityDate DESC
LIMIT 500;
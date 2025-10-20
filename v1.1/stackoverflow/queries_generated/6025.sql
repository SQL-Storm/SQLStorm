-- {"query": "6025.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 687} 
WITH
RecentActivePosts AS (
  SELECT
    p.Id,
    p.Title,
    p.PostTypeId,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.Tags,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.CreationDate >= NOW() - INTERVAL '180 days'
    AND p.PostTypeId = 1
),
TopTagActivity AS (
  SELECT
    t.TagName,
    COUNT(*) AS PostCount,
    AVG(p.ViewCount) AS AvgViews,
    AVG(p.Score) AS AvgScore
  FROM Posts p
  CROSS APPLY (
    SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
  ) t
  WHERE p.CreationDate >= NOW() - INTERVAL '365 days'
  GROUP BY t.TagName
),
UserInfluence AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COALESCE(SUM(v.BountyAmount), 0) AS TotalBounty,
    COUNT(DISTINCT p.Id) AS PostsCreated
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId = 8
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
ActivityMetrics AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    COALESCE(vt.Name, 'Unknown') AS LatestVoteType,
    v.CreationDate AS LatestVoteDate,
    CASE
      WHEN p.OwnerUserId IS NULL THEN NULL
      ELSE (SELECT AVG(VO.BountyAmount) FROM Votes VO WHERE VO.PostId = p.Id AND VO.VoteTypeId = 8)
    END AS AvgBountyOnPost
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  WHERE p.PostTypeId = 1
)
SELECT
  ra.Id AS PostId,
  ra.Title AS PostTitle,
  ra.OwnerUserId,
  ra.CreationDate AS PostCreationDate,
  ra.ViewCount,
  ra.Score,
  ra.Tags,
  ta.TagName AS TopTag,
  ta.PostCount,
  ta.AvgViews,
  ta.AvgScore,
  ui.UserId,
  ui.DisplayName AS UserDisplayName,
  ui.Reputation,
  ui.TotalBounty,
  ui.PostsCreated,
  am.LatestVoteType,
  am.LatestVoteDate,
  am.AvgBountyOnPost
FROM RecentActivePosts ra
LEFT JOIN TopTagActivity ta ON TRUE
LEFT JOIN UserInfluence ui ON ui.UserId = ra.OwnerUserId
LEFT JOIN ActivityMetrics am ON am.PostId = ra.Id
WHERE ra.rn = 1
ORDER BY ra.CreationDate DESC
LIMIT 100;
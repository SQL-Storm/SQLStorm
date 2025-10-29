-- {"query": "5948.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 983}
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
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.PostTypeId,
    p.ParentId,
    p.AcceptedAnswerId,
    u.Reputation,
    u.DisplayName AS UserDisplayName,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    L.Name AS LinkName
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN PostLinks pl ON pl.PostId = p.Id
  LEFT JOIN LinkTypes L ON pl.LinkTypeId = L.Id
  WHERE p.PostTypeId IN (1,2)
    AND p.CreationDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '180 days'
),
TagPopularity AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagCount,
    AVG(p.Score) AS AvgScore,
    AVG(p.ViewCount) AS AvgViews,
    MAX(p.LastActivityDate) AS LastActive
  FROM Tags t
  JOIN Posts p ON p.Id = t.WikiPostId OR p.Id = t.ExcerptPostId
  GROUP BY t.TagName
),
CrossRef AS (
  SELECT
    r1.Id AS PostA,
    r2.Id AS PostB,
    r1.LastActivityDate AS ActivityA,
    r2.LastActivityDate AS ActivityB,
    ROW_NUMBER() OVER (PARTITION BY r1.Id ORDER BY r2.LastActivityDate DESC) AS rn
  FROM Posts r1
  LEFT JOIN PostLinks pl ON pl.PostId = r1.Id
  LEFT JOIN Posts r2 ON pl.RelatedPostId = r2.Id
  WHERE r1.LastActivityDate IS NOT NULL
    AND r2.Id IS NOT NULL
),
WindowStats AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.UserDisplayName,
    rp.Reputation,
    rp.LastActivityDate,
    rp.ViewCount,
    rp.Score,
    rp.OwnerUserId,
    rp.PostTypeId,
    ROW_NUMBER() OVER (PARTITION BY rp.OwnerUserId ORDER BY rp.LastActivityDate DESC) AS rn_desc,
    SUM(rp.Score) OVER (PARTITION BY rp.OwnerUserId) AS TotalScorePerUser,
    AVG(rp.Score) OVER (PARTITION BY rp.OwnerUserId) AS AvgScorePerUser
  FROM RecentActivePosts rp
)
SELECT
  ws.PostId,
  ws.Title,
  ws.UserDisplayName,
  ws.Reputation,
  ws.LastActivityDate,
  ws.ViewCount,
  ws.Score,
  ws.TotalScorePerUser,
  ws.AvgScorePerUser,
  SUM(CASE WHEN ca.PostId IS NOT NULL THEN 1 ELSE 0 END) AS CommentCountOnPost,
  COUNT(vb.Id) AS ChildPostCount,
  COALESCE(tf.TagName, 'untagged') AS TopTag,
  pt.Name AS PostTypeName,
  (CASE WHEN EXISTS (
    SELECT 1
    FROM Votes v
    WHERE v.PostId = ws.PostId
      AND v.VoteTypeId = 2
      AND v.CreationDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30 days'
  ) THEN TRUE ELSE FALSE END) AS RecentlyUpvoted,
  CASE
    WHEN ws.Score > 0 THEN ws.Score * 1.0 / (ws.ViewCount + 1)
    ELSE 0
  END AS ScorePerView,
  STRING_AGG(DISTINCT L.Name, ',') AS LinkedTypes
FROM WindowStats ws
LEFT JOIN Comments ca ON ca.PostId = ws.PostId
LEFT JOIN Posts vb ON vb.ParentId = ws.PostId
LEFT JOIN LATERAL (
  SELECT t.Id, t.TagName
  FROM Tags t
  WHERE t.WikiPostId = ws.PostId OR t.ExcerptPostId = ws.PostId
  LIMIT 1
) tf ON TRUE
LEFT JOIN PostLinks pl2 ON pl2.PostId = ws.PostId
LEFT JOIN LinkTypes L ON pl2.LinkTypeId = L.Id
LEFT JOIN PostTypes pt ON ws.PostTypeId = pt.Id
GROUP BY
  ws.PostId, ws.Title, ws.UserDisplayName, ws.Reputation, ws.LastActivityDate,
  ws.ViewCount, ws.Score, ws.TotalScorePerUser, ws.AvgScorePerUser,
  pt.Name, ws.PostTypeId, tf.TagName
ORDER BY ws.TotalScorePerUser DESC
LIMIT 100;
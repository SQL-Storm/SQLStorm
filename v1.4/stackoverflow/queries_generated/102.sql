-- {"query": "102.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 1369} 
WITH
RecentPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    u.DisplayName AS OwnerName,
    p.LastActivityDate,
    p.Tags
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1 -- Questions
),
Ranked AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.ViewCount,
    rp.Score,
    rp.OwnerUserId,
    rp.OwnerName,
    ROW_NUMBER() OVER (ORDER BY rp.LastActivityDate DESC, rp.Score DESC, rp.ViewCount DESC) AS rn
  FROM RecentPosts rp
),
TagStats AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagQuestionCount,
    AVG(q.Score) AS AvgQuestionScore
  FROM Tags t
  JOIN Posts q ON q.Tags LIKE '%' || t.TagName || '%' AND q.PostTypeId = 1
  GROUP BY t.TagName
),
TopContributors AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(p.Id) AS PostsCount,
    SUM(p.Score) AS TotalScore
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
  ORDER BY TotalScore DESC NULLS LAST
  LIMIT 100
),
RecentClosed AS (
  SELECT
    ph.PostId,
    ph.PostHistoryTypeId,
    ph.CreationDate,
    ph.Comment
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId = 10 -- Post Closed
),
Aggregated AS (
  SELECT
    r.PostId,
    r.Title,
    r.LastActivityDate,
    r.ViewCount,
    r.Score,
    r.OwnerUserId,
    rp.DisplayName AS OwnerDisplayName,
    COALESCE((SELECT STRING_AGG(CONCAT_ws(' | ', c.Text, c.UserDisplayName), ' || ')
              FROM Comments c
              WHERE c.PostId = r.PostId), '') AS CommentsSummary,
    (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = r.PostId AND v.VoteTypeId = 2) AS AvgUpMod,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = r.PostId) AS LinkCount
  FROM Ranked r
  LEFT JOIN Users rp ON r.OwnerUserId = rp.Id
)
SELECT
  a.PostId,
  a.Title,
  a.OwnerDisplayName,
  a.LastActivityDate,
  a.ViewCount,
  a.Score,
  a.OwnerUserId,
  a.CommentsSummary,
  a.AvgUpMod,
  a.LinkCount,
  tc.TagName,
  tc.TagQuestionCount,
  tc.AvgQuestionScore
FROM Aggregated a
LEFT JOIN Tags t ON a.PostId = t.WikiPostId OR a.PostId = t.ExcerptPostId
LEFT JOIN TagStats tc ON tc.TagName = t.TagName
UNION ALL
SELECT
  NULL AS PostId,
  'Top 100 Contributors Benchmark' AS Title,
  NULL AS OwnerDisplayName,
  NULL AS LastActivityDate,
  NULL AS ViewCount,
  NULL AS Score,
  NULL AS OwnerUserId,
  NULL AS CommentsSummary,
  NULL AS AvgUpMod,
  NULL AS LinkCount,
  NULL AS TagName,
  NULL AS TagQuestionCount,
  NULL AS AvgQuestionScore
FROM TopContributors
ORDER BY LastActivityDate DESC NULLS LAST, PostId ASC NULLS LAST;
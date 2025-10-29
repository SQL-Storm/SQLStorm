-- {"query": "5922.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 876} 
WITH RecentActivePosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.CreationDate,
    p.Title,
    p.Tags,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.AnswerCount,
    p.LastActivityDate,
    p.LastEditorUserId,
    p.LastEditDate
  FROM Posts p
  WHERE p.CreationDate >= now() - INTERVAL '30 days'
),
TagAnalytics AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagPostCount,
    AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
    SUM(p.ViewCount) AS TotalViews
  FROM (
      SELECT
        unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName,
        p.Id
      FROM Posts p
      WHERE p.PostTypeId = 1
  ) ttags
  JOIN Posts p ON p.Id = ttags.Id
  GROUP BY t.TagName
),
TopPartners AS (
  SELECT
    u1.Id AS UserA,
    u2.Id AS UserB,
    COUNT(*) AS MutualCount
  FROM Users u1
  JOIN PostHistory ph1 ON ph1.UserId = u1.Id
  JOIN PostHistory ph2 ON ph2.UserId = u1.Id
  JOIN Posts p1 ON ph1.PostId = p1.Id
  JOIN Posts p2 ON ph2.PostId = p2.Id
  JOIN Votes v1 ON v1.PostId = p1.Id AND v1.UserId = u1.Id
  JOIN Votes v2 ON v2.PostId = p2.Id AND v2.UserId = u1.Id
  WHERE p1.OwnerUserId IS NOT NULL
    AND p2.OwnerUserId IS NOT NULL
  GROUP BY u1.Id, u2.Id
  ORDER BY MutualCount DESC
  LIMIT 50
)
SELECT
  r.PostId,
  r.PostTypeId,
  r.Title,
  r.Tags,
  r.OwnerUserId,
  r.Score,
  r.ViewCount,
  r.CommentCount,
  r.AnswerCount,
  r.LastActivityDate,
  r.LastEditDate,
  ua.DisplayName AS OwnerDisplayName,
  du.DisplayName AS LastEditorDisplayName,
  COALESCE(vn.VoteNet, 0) AS NetVotes,
  ca.TagName,
  ta.TagPostCount,
  ta.AvgQuestionScore,
  ta.TotalViews,
  tp.UserA,
  tp.UserB,
  tp.MutualCount
FROM RecentActivePosts r
LEFT JOIN Users ua ON r.OwnerUserId = ua.Id
LEFT JOIN Users du ON r.LastEditorUserId = du.Id
LEFT JOIN (
  SELECT
    p.Id,
    SUM(CASE WHEN v.VoteTypeId IN (2) THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId IN (3) THEN 1 ELSE 0 END) AS DownVotes,
    SUM(CASE WHEN v.VoteTypeId IN (2,3) THEN 1 ELSE 0 END) AS VoteNet
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY p.Id
) vn ON r.Id = vn.Id
LEFT JOIN (
  SELECT
    TagName,
    COUNT(*) AS TagPostCount,
    AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScore,
    SUM(p.ViewCount) AS TotalViews
  FROM (
    SELECT
      unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName,
      p.Id,
      p.PostTypeId,
      p.Score,
      p.ViewCount
    FROM Posts p
  ) pp
  GROUP BY TagName
) ta ON true
LEFT JOIN TagAnalytics ca ON ca.TagName = ta.TagName
LEFT JOIN TopPartners tp ON true
ORDER BY r.LastActivityDate DESC
LIMIT 100;
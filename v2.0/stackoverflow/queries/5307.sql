-- {"query": "5307.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 708}
WITH recent_activity AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.OwnerUserId,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.FavoriteCount,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '180 days'
),
owner_stats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    COUNT(r.PostId) FILTER (WHERE r.PostId IS NOT NULL) AS recent_posts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS total_question_score,
    SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS total_answer_score
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN recent_activity r ON r.PostId = p.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
top_tags AS (
  SELECT
    t.TagName AS Name,
    SUM(t.Count) AS tag_count
  FROM Tags t
  GROUP BY t.TagName
  ORDER BY tag_count DESC
  LIMIT 10
),
votes_by_post AS (
  SELECT PostId, SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalVotes
  FROM Votes
  GROUP BY PostId
),
complex_metrics AS (
  SELECT
    ry.PostId,
    py.Title AS PostTitle,
    py.OwnerUserId,
    py.LastActivityDate,
    (py.Score + COALESCE(vs.TotalVotes, 0)) AS composite_score,
    CASE WHEN py.ViewCount > 1000 THEN TRUE ELSE FALSE END AS is_hot,
    ARRAY_AGG(DISTINCT lt.Name) FILTER (WHERE lt.Name IS NOT NULL) AS link_types,
    COUNT(pl.Id) AS link_count,
    COUNT(c.Id) AS comment_count
  FROM recent_activity ry
  JOIN Posts py ON py.Id = ry.PostId
  LEFT JOIN votes_by_post vs ON vs.PostId = ry.PostId
  LEFT JOIN PostLinks pl ON pl.PostId = ry.PostId
  LEFT JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
  LEFT JOIN Comments c ON c.PostId = ry.PostId
  WHERE ry.rn = 1
  GROUP BY
    ry.PostId,
    py.Title,
    py.OwnerUserId,
    py.LastActivityDate,
    py.Score,
    vs.TotalVotes,
    py.ViewCount
)
SELECT
  cm.PostId,
  cm.PostTitle,
  cm.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  cm.LastActivityDate,
  cm.composite_score,
  cm.is_hot,
  cm.link_types,
  cm.link_count,
  cm.comment_count,
  os.Reputation,
  os.total_question_score,
  os.total_answer_score,
  tt.Name AS TopTag
FROM complex_metrics cm
JOIN Users u ON u.Id = cm.OwnerUserId
LEFT JOIN owner_stats os ON os.UserId = u.Id
LEFT JOIN top_tags tt ON 1 = 1
ORDER BY cm.composite_score DESC, cm.LastActivityDate DESC
LIMIT 100;
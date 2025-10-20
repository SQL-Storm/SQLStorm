-- {"query": "99.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 745} 
WITH
recent_top_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    ROW_NUMBER() OVER (PARTITION BY p.Tags ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1 -- Question
    AND p.CreationDate >= NOW() - INTERVAL '180 days'
    AND p.ClosedDate IS NULL
),
tag_burst AS (
  SELECT
    unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), ''><'')) AS TagName,
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate
  FROM Posts p
  WHERE p.PostTypeId = 1
),
top_tags AS (
  SELECT
    TagName,
    COUNT(*) AS Questions,
    SUM(p.Score) AS ScoreSum,
    AVG(p.ViewCount) AS AvgViews
  FROM tag_burst tb
  JOIN Posts p ON p.Id = tb.PostId
  GROUP BY TagName
  ORDER BY ScoreSum DESC, Questions DESC
  LIMIT 20
),
correlated_activity AS (
  SELECT
    q.PostId,
    q.Title,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    q.OwnerDisplayName,
    (SELECT COUNT(*) FROM Posts x WHERE x.OwnerUserId = q.OwnerUserId AND x.CreationDate > q.CreationDate) AS LaterPostsByOwner,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = q.PostId) AS CommentCount,
    EXISTS (
      SELECT 1
      FROM Votes v
      WHERE v.PostId = q.PostId
        AND v.VoteTypeId IN (2,3) -- UpMod/DownMod
        AND v.CreationDate > q.CreationDate - INTERVAL '7 days'
    ) AS HadRecentVotes
  FROM Posts q
  WHERE q.PostTypeId = 1
    AND q.CreationDate >= NOW() - INTERVAL '365 days'
    AND q.OwnerUserId IS NOT NULL
)
SELECT
  up.OwnerDisplayName,
  up.PostId,
  up.Title,
  up.CreationDate,
  up.Score,
  up.ViewCount,
  up.CommentCount,
  up.LaterPostsByOwner,
  c.HadRecentVotes,
  json_agg(DISTINCT jsonb_build_object(
    'Tag', t.TagName,
    'Questions', t.Questions,
    'ScoreSum', t.ScoreSum,
    'AvgViews', t.AvgViews
  )) FILTER (WHERE t.TagName IS NOT NULL) AS TopTagsSummary
FROM correlated_activity up
LEFT JOIN (
  SELECT
    qt.TagName,
    qt.Questions,
    qt.ScoreSum,
    qt.AvgViews
  FROM top_tags tt
) t ON true
GROUP BY
  up.OwnerDisplayName,
  up.PostId,
  up.Title,
  up.CreationDate,
  up.Score,
  up.ViewCount,
  up.CommentCount,
  up.LaterPostsByOwner,
  up.HadRecentVotes
ORDER BY up.CreationDate DESC
LIMIT 100;
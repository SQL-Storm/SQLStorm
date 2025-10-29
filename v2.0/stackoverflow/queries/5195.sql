-- {"query": "5195.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 738}
WITH recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.AnswerCount,
    p.CommentCount
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
),
tag_stats AS (
  SELECT
    tag,
    COUNT(*) AS question_count,
    AVG(p.Score) AS avg_score,
    SUM(p.ViewCount) AS total_views
  FROM Posts p
  JOIN recent_questions r ON r.PostId = p.Id
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS tag
  ) t
  GROUP BY tag
),
top_tags AS (
  SELECT tag, question_count, avg_score, total_views
  FROM tag_stats
  ORDER BY total_views DESC
  LIMIT 5
),
correlated_subselect AS (
  SELECT
    r.PostId,
    r.Title,
    r.CreationDate,
    r.ViewCount,
    r.Score,
    (
      SELECT AVG(v.BountyAmount)
      FROM Votes v
      WHERE v.PostId = r.PostId
        AND v.VoteTypeId = 2
        AND v.CreationDate >= r.CreationDate
    ) AS avg_upmod_after_creation
  FROM recent_questions r
),
window_anal AS (
  SELECT
    p.Id AS post_id,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.ViewCount,
    p.Score,
    SUM(p.ViewCount) OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_views_by_user
  FROM Posts p
  WHERE p.PostTypeId = 1
)
SELECT
  r.PostId AS post_id,
  r.Title,
  r.CreationDate,
  w.LastActivityDate,
  r.ViewCount,
  r.Score,
  w.running_views_by_user,
  COALESCE(a.avg_upmod_after_creation, 0) AS avg_upmod_after_creation
FROM correlated_subselect r
JOIN window_anal w ON w.post_id = r.PostId
LEFT JOIN (
  SELECT
    p.Id,
    AVG(CASE WHEN v.VoteTypeId = 2 THEN v.BountyAmount ELSE NULL END) AS avg_upmod_after_creation
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE v.VoteTypeId = 2
  GROUP BY p.Id
) a ON a.Id = r.PostId

UNION ALL

SELECT
  t.post_id,
  t.Title,
  t.CreationDate,
  t.LastActivityDate,
  t.ViewCount,
  t.Score,
  CAST(NULL AS bigint) AS running_views_by_user,
  0 AS avg_upmod_after_creation
FROM (
  SELECT
    p.Id AS post_id,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.ViewCount,
    p.Score
  FROM Posts p
  WHERE p.PostTypeId = 1
) t
ORDER BY LastActivityDate DESC
LIMIT 100;
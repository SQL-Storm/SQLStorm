-- {"query": "5891.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 688} 
WITH recent_top_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.ViewCount,
    p.Score,
    p.CreationDate,
    p.OwnerUserId,
    p.Tags,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate ASC) AS rn_owner
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Question
    AND p.ClosedDate IS NULL
),
tag_stats AS (
  SELECT
    unnest(string_to_array(TRIM(BOTH '' FROM p.Tags), '><')) AS tag,
    COUNT(*) AS questions_with_tag,
    MAX(p.Score) AS max_score_for_tag,
    AVG(p.ViewCount) AS avg_views_per_tag
  FROM Posts p
  WHERE p.PostTypeId = 1
  GROUP BY unnest(string_to_array(TRIM(BOTH '' FROM p.Tags), '><'))
),
complex_derived AS (
  SELECT
    r.PostId,
    r.Title,
    r.ViewCount,
    r.Score,
    r.CreationDate,
    r.OwnerUserId,
    r.Tags,
    t.tag,
    t.questions_with_tag,
    t.max_score_for_tag,
    t.avg_views_per_tag,
    CASE
      WHEN r.ViewCount > 1000 THEN 'Heavy'
      WHEN r.ViewCount > 100 THEN 'Medium'
      ELSE 'Light'
    END AS popularity_bucket,
    CASE
      WHEN r.Score >= 10 THEN true
      ELSE false
    END AS highly_scored
  FROM recent_top_questions r
  LEFT JOIN tag_stats t ON t.tag = ANY(string_to_array(TRIM(BOTH '' FROM r.Tags), '><'))
  WHERE r.rn_owner = 1
),
activity_window AS (
  SELECT
    c.*,
    LAG(c.ViewCount) OVER (PARTITION BY c.OwnerUserId ORDER BY c.CreationDate) AS prev_views,
    LEAD(c.ViewCount) OVER (PARTITION BY c.OwnerUserId ORDER BY c.CreationDate) AS next_views,
    -- time distance to next activity
    EXTRACT(EPOCH FROM (LEAD(c.CreationDate) OVER (PARTITION BY c.OwnerUserId ORDER BY c.CreationDate) - c.CreationDate)) AS seconds_to_next
  FROM complex_derived c
),
final_select AS (
  SELECT
    a.PostId,
    a.Title,
    a.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    a.ViewCount,
    a.Score,
    a.CreationDate,
    a.Tags,
    a.popularity_bucket,
    a.highly_scored,
    a.max_score_for_tag,
    a.avg_views_per_tag,
    a.seconds_to_next,
    a.prev_views,
    a.next_views
  FROM activity_window a
  LEFT JOIN Users u ON u.Id = a.OwnerUserId
  WHERE a.popularity_bucket IS NOT NULL
    AND a.highly_scored = TRUE
  ORDER BY a.Score DESC NULLS LAST, a.ViewCount DESC NULLS LAST
  LIMIT 200
)
SELECT *
FROM final_select
OFFSET 0 ROWS
FETCH NEXT 200 ROWS ONLY;
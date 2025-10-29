-- {"query": "5765.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 502} 
WITH
RecentActivePosts AS (
  SELECT
    p.Id,
    p.Title,
    p.PostTypeId,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.LastActivityDate >= NOW() - INTERVAL '30 days'
),
TopTags AS (
  SELECT
    t.TagName AS tag,
    AVG(p.Score) AS avg_score,
    SUM(p.ViewCount) AS total_views,
    COUNT(*) AS post_count
  FROM RecentActivePosts p
  JOIN UNNEST(string_to_array(p.Tags, ',') ) AS tag_name(tag) ON true
  GROUP BY tag
  HAVING COUNT(*) > 5
),
TagCrossStats AS (
  SELECT
    tt.tag,
    tt.post_count,
    tt.avg_score,
    tt.total_views,
    AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) OVER (PARTITION BY tt.tag) AS avg_answer_score,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY tt.tag) AS upvotes_for_tag,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY tt.tag) AS downvotes_for_tag
  FROM TopTags tt
  LEFT JOIN LATERAL (
    SELECT *
    FROM Posts p
    WHERE p.Id IN (
      SELECT PostId FROM PostLinks pl
      WHERE pl.RelatedPostId = p.Id AND pl.LinkTypeId = 1
    )
  ) p ON true
  LEFT JOIN Votes v ON v.PostId = p.Id
)
SELECT
  tt.tag,
  tt.post_count,
  tt.avg_score,
  tt.total_views,
  COALESCE(a.avg_answer_score, 0) AS avg_answer_score,
  COALESCE(a.upvotes_for_tag, 0) AS upvotes_for_tag,
  COALESCE(a.downvotes_for_tag, 0) AS downvotes_for_tag
FROM TagCrossStats a
JOIN (
  SELECT DISTINCT tag FROM TopTags
) tt ON true
ORDER BY tt.tag
LIMIT 100;
-- {"query": "5851.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 589} 
WITH recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.AnswerCount,
    p.LastActivityDate
  FROM Posts p
  WHERE p.PostTypeId = 1 -- questions
    AND p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '365 days'
),
top_tags AS (
  SELECT
    t.TagName,
    AVG(p.Score) AS avg_score,
    MAX(p.ViewCount) AS max_views,
    COUNT(*) AS q_count
  FROM recent_questions rq
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substr(rq.Tags, 2, length(rq.Tags)-2), '><')) AS TagName
  ) t
  JOIN Posts p ON p.Id = rq.PostId
  GROUP BY t.TagName
),
tag_metrics AS (
  SELECT
    TagName,
    SUM(CASE WHEN avg_score > 0 THEN 1 ELSE 0 END) AS positive_score_posts,
    SUM(CASE WHEN avg_score < 0 THEN 1 ELSE 0 END) AS negative_score_posts,
    AVG(avg_score) AS average_score_per_tag
  FROM top_tags
  GROUP BY TagName
),
complex_filter AS (
  SELECT
    rq.PostId,
    rq.Title,
    rq.CreationDate,
    rq.OwnerUserId,
    rq.Tags,
    rq.Score,
    rq.ViewCount,
    rq.CommentCount,
    rq.AnswerCount,
    rq.LastActivityDate,
    tm.TagName
  FROM recent_questions rq
  LEFT JOIN LATERAL (
    SELECT unnest(string_to_array(substr(rq.Tags, 2, length(rq.Tags)-2), '><')) AS TagName
  ) t ON true
  LEFT JOIN tag_metrics tm ON tm.TagName = t.TagName
  WHERE (rq.Score > 5 AND rq.ViewCount > 100) OR
        (rq.Score BETWEEN -2 AND 2 AND rq.ViewCount > 500)
)
SELECT
  cf.PostId,
  cf.Title,
  cf.CreationDate,
  cf.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  cf.Tags,
  cf.Score,
  cf.ViewCount,
  cf.CommentCount,
  cf.AnswerCount,
  cf.LastActivityDate,
  cf.TagName,
  tm.positive_score_posts,
  tm.negative_score_posts,
  tm.average_score_per_tag
FROM complex_filter cf
LEFT JOIN Users u ON cf.OwnerUserId = u.Id
LEFT JOIN tag_metrics tm ON tm.TagName = cf.TagName
ORDER BY cf.LastActivityDate DESC, cf.ViewCount DESC
LIMIT 100;
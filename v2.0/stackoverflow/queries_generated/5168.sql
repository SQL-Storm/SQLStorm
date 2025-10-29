-- {"query": "5168.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 640} 
WITH top_tags AS (
  SELECT
    t.TagName,
    t.Count,
    ROW_NUMBER() OVER (ORDER BY t.Count DESC, t.TagName ASC) AS rn
  FROM Tags t
  WHERE t.IsModeratorOnly = 0 AND t.IsRequired = 0
),
recent_activity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.ViewCount,
    p.Score,
    p.AnswerCount,
    p.CommentCount,
    p.Tags,
    v.VoteTypeId,
    v.CreationDate AS VoteDate,
    u.Reputation,
    u.DisplayName AS UserName,
    bh.PostHistoryTypeId,
    bh.CreationDate AS HistoryDate,
    bh.Comment
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN Users u ON u.Id = p.OwnerUserId
  LEFT JOIN PostHistory bh ON bh.PostId = p.Id
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= NOW() - INTERVAL '180 days'
),
complex_calc AS (
  SELECT
    t.TagName,
    t.Count,
    (t.Count * 1.0) / NULLIF((SELECT SUM(ct.Count) FROM Tags ct WHERE ct.IsModeratorOnly = 0 AND ct.IsRequired = 0), 0) AS tag_popularity,
    CASE
      WHEN p.OwnerUserId IS NULL THEN 'anonymous'
      WHEN u.Reputation < 1000 THEN 'low'
      WHEN u.Reputation BETWEEN 1000 AND 10000 THEN 'mid'
      ELSE 'high'
    END AS user_tier,
    DATE_TRUNC('hour', p.CreationDate) AS creation_hour,
    ARRAY_AGG(DISTINCT p.Id) AS post_ids
  FROM top_tags t
  LEFT JOIN recent_activity p ON p.Tags LIKE '%' || t.TagName || '%'
  LEFT JOIN Users u ON u.Id = p.OwnerUserId
  GROUP BY t.TagName, t.Count, p.OwnerUserId, u.Reputation, creation_hour
),
final_result AS (
  SELECT
    c.tag_popularity,
    c.user_tier,
    c.creation_hour,
    c.post_ids,
    c.TagName
  FROM complex_calc c
  ORDER BY c.tag_popularity DESC NULLS LAST, c.creation_hour ASC
  LIMIT 100
)
SELECT
  fr.TagName AS tag,
  fr.creation_hour AS hour,
  fr.user_tier AS user_tier,
  fr.tag_popularity AS popularity,
  bv.post_ids AS posts_with_tag
FROM final_result fr
LEFT JOIN (
  SELECT
    t.TagName,
    ARRAY_AGG(p.Id) AS post_ids
  FROM Posts p
  JOIN Tags t ON p.Tags LIKE '%' || t.TagName || '%'
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
) bv ON bv.TagName = fr.TagName
;
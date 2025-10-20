-- {"query": "2.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 750} 
WITH recent_comments AS (
  SELECT
    c.PostId,
    AVG(c.Score) AS avg_comment_score,
    COUNT(*) AS comment_count
  FROM Comments c
  WHERE c.CreationDate >= NOW() - INTERVAL '30 days'
  GROUP BY c.PostId
),
top_users AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.LastAccessDate DESC) AS rn
  FROM Users u
  WHERE u.Reputation > 1000
),
hot_tags AS (
  SELECT
    t.TagName,
    SUM(p.Score) AS total_score,
    AVG(p.ViewCount) AS avg_views,
    COUNT(*) AS post_count
  FROM Posts p
  JOIN UNNEST(string_to_array(p.Tags, '><')) AS t(TagName) ON true
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
),
complex_posts AS (
  SELECT
    p.Id,
    p.Title,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.LastActivityDate,
    p.Tags,
    COALESCE(r.avg_comment_score, 0) AS avg_comment_score,
    COALESCE(r.comment_count, 0) AS comment_count
  FROM Posts p
  LEFT JOIN recent_comments r ON p.Id = r.PostId
  LEFT JOIN top_users nu ON nu.UserId = p.OwnerUserId
  WHERE
    p.PostTypeId = 1
    AND p.LastActivityDate >= NOW() - INTERVAL '90 days'
    AND (p.Score > 0 OR p.ViewCount > 100)
    AND (p.Tags IS NOT NULL)
),
aggregated AS (
  SELECT
    cp.*,
    ht.total_score AS tag_total_score,
    ht.avg_views AS tag_avg_views,
    ht.post_count AS tag_post_count
  FROM complex_posts cp
  LEFT JOIN hot_tags ht ON cp.Tags ILIKE '%' || ht.TagName || '%'
),
final AS (
  SELECT
    a.Id AS post_id,
    a.Title,
    a.OwnerUserId,
    a.Score,
    a.ViewCount,
    a.CommentCount,
    a.LastActivityDate,
    a.Tags,
    a.avg_comment_score,
    a.comment_count,
    a.tag_total_score,
    a.tag_avg_views,
    a.tag_post_count,
    CASE
      WHEN a.Score > 0 AND a.comment_count > 5 THEN 'hot-interaction'
      WHEN a.tag_post_count > 100 THEN 'popular-tag'
      ELSE 'standard'
    END AS category,
    EXISTS (
      SELECT 1
      FROM Votes v
      WHERE v.PostId = a.Id
        AND v.VoteTypeId = 2
        AND v.CreationDate >= NOW() - INTERVAL '7 days'
    ) AS had_recent_upvote
  FROM aggregated a
)
SELECT
  f.post_id,
  f.Title,
  f.OwnerUserId,
  f.Score,
  f.ViewCount,
  f.CommentCount,
  f.LastActivityDate,
  f.Tags,
  f.avg_comment_score,
  f.comment_count,
  f.tag_total_score,
  f.tag_avg_views,
  f.tag_post_count,
  f.category,
  f.had_recent_upvote
FROM final f
ORDER BY
  f.category,
  f.Score DESC,
  f.LastActivityDate DESC
LIMIT 200;
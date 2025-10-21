-- {"query": "16072.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 2123}

WITH user_activity_metrics AS (
  SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    COALESCE(u.Location, 'Unknown') AS Location,
    COUNT(DISTINCT p.Id) AS total_posts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS question_count,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS answer_count,
    AVG(CASE WHEN p.Score IS NOT NULL THEN p.Score ELSE 0 END) AS avg_post_score,
    SUM(COALESCE(p.ViewCount, 0)) AS total_views,
    ROW_NUMBER() OVER (PARTITION BY SUBSTRING(COALESCE(u.Location, 'N/A'), 1, 20) ORDER BY u.Reputation DESC) AS location_rank,
    DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS post_activity_rank
  FROM Users u
  LEFT OUTER JOIN Posts p ON u.Id = p.OwnerUserId
  WHERE u.Reputation > 100 
    AND u.CreationDate >= '2015-01-01'
    AND (p.CreationDate IS NULL OR p.CreationDate >= '2015-01-01')
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
  HAVING COUNT(DISTINCT p.Id) > 5 OR u.Reputation > 1000
),
badge_statistics AS (
  SELECT 
    b.UserId,
    COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS gold_badges,
    COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS silver_badges,
    COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS bronze_badges,
    STRING_AGG(DISTINCT CASE WHEN b.Class = 1 THEN b.Name END, ', ') AS gold_badge_names,
    MAX(b.Date) AS last_badge_date,
    COUNT(*) FILTER (WHERE b.TagBased = 1) AS tag_based_badge_count
  FROM Badges b
  WHERE b.Date >= '2015-01-01'
  GROUP BY b.UserId
),
post_interaction_summary AS (
  SELECT 
    p.Id AS post_id,
    p.OwnerUserId,
    p.PostTypeId,
    p.Score,
    p.Title,
    p.CreationDate AS post_date,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 0) AS positive_comment_count,
    (SELECT AVG(v.CreationDate - p.CreationDate) 
     FROM Votes v 
     WHERE v.PostId = p.Id AND v.VoteTypeId IN (2, 3)
    ) AS avg_vote_time_lag,
    EXISTS(
      SELECT 1 FROM PostLinks pl 
      WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3
    ) AS is_duplicate,
    COALESCE(
      (SELECT u2.DisplayName 
       FROM Posts p2 
       JOIN Users u2 ON p2.OwnerUserId = u2.Id 
       WHERE p2.Id = p.AcceptedAnswerId),
      'No Accepted Answer'
    ) AS accepted_answerer,
    LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS prev_post_score,
    LEAD(p.CreationDate, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) - p.CreationDate AS time_to_next_post
  FROM Posts p
  WHERE p.PostTypeId IN (1, 2)
    AND p.CreationDate >= '2016-01-01'
    AND p.Score IS NOT NULL
),
tag_performance AS (
  SELECT 
    UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')) AS tag_name,
    COUNT(*) AS tag_usage_count,
    AVG(p.Score) AS avg_tag_score,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.ViewCount) AS median_views
  FROM Posts p
  WHERE p.PostTypeId = 1 
    AND p.Tags IS NOT NULL 
    AND LENGTH(p.Tags) > 2
    AND p.CreationDate >= '2017-01-01'
  GROUP BY tag_name
  HAVING COUNT(*) >= 10
)
SELECT 
  uam.DisplayName,
  UPPER(COALESCE(SUBSTRING(uam.Location, 1, 30), 'UNKNOWN')) AS normalized_location,
  uam.Reputation,
  uam.total_posts,
  uam.question_count,
  uam.answer_count,
  ROUND(uam.avg_post_score::numeric, 2) AS avg_score,
  uam.total_views,
  uam.location_rank,
  COALESCE(bs.gold_badges, 0) AS gold_count,
  COALESCE(bs.silver_badges, 0) AS silver_count,
  COALESCE(bs.bronze_badges, 0) AS bronze_count,
  COALESCE(bs.gold_badge_names, 'None') AS gold_achievements,
  COALESCE(bs.tag_based_badge_count, 0) AS tag_badges,
  (SELECT COUNT(*) 
   FROM post_interaction_summary pis 
   WHERE pis.OwnerUserId = uam.Id 
     AND pis.positive_comment_count > 3
  ) AS highly_commented_posts,
  (SELECT COUNT(DISTINCT pis2.post_id)
   FROM post_interaction_summary pis2
   WHERE pis2.OwnerUserId = uam.Id
     AND pis2.is_duplicate = TRUE
  ) AS duplicate_post_count,
  (SELECT STRING_AGG(DISTINCT tp.tag_name, '|')
   FROM Posts p
   CROSS JOIN LATERAL UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(COALESCE(p.Tags, ''))-2), '><')) AS tp(tag_name)
   WHERE p.OwnerUserId = uam.Id 
     AND p.PostTypeId = 1
   LIMIT 5
  ) AS top_tags_used,
  CASE 
    WHEN uam.Reputation > 10000 THEN 'Elite'
    WHEN uam.Reputation > 5000 THEN 'Expert'
    WHEN uam.Reputation > 1000 THEN 'Intermediate'
    ELSE 'Beginner'
  END AS reputation_tier,
  EXTRACT(YEAR FROM AGE(CURRENT_TIMESTAMP, uam.CreationDate)) * 12 + 
    EXTRACT(MONTH FROM AGE(CURRENT_TIMESTAMP, uam.CreationDate)) AS months_active,
  uam.total_posts::float / NULLIF(EXTRACT(YEAR FROM AGE(CURRENT_TIMESTAMP, uam.CreationDate)) * 12 + 
    EXTRACT(MONTH FROM AGE(CURRENT_TIMESTAMP, uam.CreationDate)), 0) AS posts_per_month
FROM user_activity_metrics uam
LEFT JOIN badge_statistics bs ON uam.Id = bs.UserId
WHERE uam.location_rank <= 10
  AND uam.post_activity_rank <= 1000
  AND (bs.gold_badges IS NULL OR bs.gold_badges >= 0)
  AND NOT EXISTS (
    SELECT 1 FROM Votes v 
    JOIN Posts p ON v.PostId = p.Id 
    WHERE p.OwnerUserId = uam.Id 
      AND v.VoteTypeId = 12 
    HAVING COUNT(*) > 5
  )
ORDER BY 
  CASE WHEN bs.gold_badges > 0 THEN 1 ELSE 2 END,
  uam.Reputation DESC,
  uam.total_posts DESC
LIMIT 100;

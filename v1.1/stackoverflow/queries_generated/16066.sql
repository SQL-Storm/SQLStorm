-- {"query": "16066.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 156445, "output_tokens": 144508} 

WITH user_activity_metrics AS (
  SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.Location,
    COUNT(DISTINCT p.Id) as post_count,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as question_count,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as answer_count,
    AVG(CASE WHEN p.Score IS NOT NULL THEN p.Score ELSE 0 END) as avg_post_score,
    STRING_AGG(DISTINCT SUBSTRING(COALESCE(u.Location, 'Unknown'), 1, 20), ', ') OVER (PARTITION BY COALESCE(SUBSTRING(u.Location, 1, 10), 'N/A')) as location_cluster
  FROM Users u
  LEFT OUTER JOIN Posts p ON u.Id = p.OwnerUserId
  WHERE u.Reputation > 1000 
    AND u.CreationDate >= '2020-01-01'
    AND (u.Location IS NULL OR LENGTH(TRIM(u.Location)) > 0)
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
  HAVING COUNT(DISTINCT p.Id) > 5
),
badge_rankings AS (
  SELECT 
    b.UserId,
    b.Name as badge_name,
    b.Class,
    COUNT(*) as badge_count,
    ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY COUNT(*) DESC, MIN(b.Date)) as badge_rank,
    DENSE_RANK() OVER (ORDER BY COUNT(*) DESC) as global_badge_rank,
    LAG(COUNT(*), 1, 0) OVER (PARTITION BY b.UserId ORDER BY b.Class) as prev_class_count,
    LEAD(b.Date, 1) OVER (PARTITION BY b.UserId, b.Name ORDER BY b.Date) as next_badge_date
  FROM Badges b
  WHERE b.Date >= '2019-01-01'
  GROUP BY b.UserId, b.Name, b.Class
),
post_interaction_stats AS (
  SELECT 
    p.Id as post_id,
    p.OwnerUserId,
    p.PostTypeId,
    p.Score,
    p.ViewCount,
    COALESCE(p.CommentCount, 0) + COALESCE(p.AnswerCount, 0) as total_interactions,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) as upvote_count,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) as downvote_count,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 1) as linked_count,
    CASE 
      WHEN p.ViewCount > 10000 THEN 'Viral'
      WHEN p.ViewCount > 1000 THEN 'Popular'
      WHEN p.ViewCount > 100 THEN 'Moderate'
      ELSE 'Low'
    END as popularity_tier,
    EXTRACT(EPOCH FROM (COALESCE(p.LastActivityDate, p.CreationDate) - p.CreationDate)) / 86400.0 as activity_duration_days
  FROM Posts p
  WHERE p.CreationDate >= '2020-01-01'
    AND p.OwnerUserId IS NOT NULL
    AND (p.PostTypeId = 1 OR p.PostTypeId = 2)
),
tag_expertise AS (
  SELECT 
    p.OwnerUserId,
    UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) as tag,
    COUNT(*) as tag_usage_count,
    AVG(p.Score) as avg_tag_score,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) as median_tag_score
  FROM Posts p
  WHERE p.PostTypeId = 1 
    AND p.Tags IS NOT NULL 
    AND LENGTH(p.Tags) > 2
    AND p.OwnerUserId IS NOT NULL
  GROUP BY p.OwnerUserId, UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'))
  HAVING COUNT(*) >= 3
)
SELECT 
  uam.DisplayName,
  COALESCE(uam.Location, 'Unknown Location') as user_location,
  uam.Reputation,
  uam.post_count,
  uam.question_count,
  uam.answer_count,
  ROUND(uam.avg_post_score::numeric, 2) as avg_score,
  COUNT(DISTINCT br.badge_name) as unique_badges,
  SUM(CASE WHEN br.Class = 1 THEN br.badge_count ELSE 0 END) as gold_badges,
  SUM(CASE WHEN br.Class = 2 THEN br.badge_count ELSE 0 END) as silver_badges,
  SUM(CASE WHEN br.Class = 3 THEN br.badge_count ELSE 0 END) as bronze_badges,
  ROUND(AVG(pis.total_interactions)::numeric, 2) as avg_interactions_per_post,
  MAX(pis.ViewCount) as max_views_single_post,
  STRING_AGG(DISTINCT pis.popularity_tier, '|' ORDER BY pis.popularity_tier) as popularity_distribution,
  (SELECT te.tag 
   FROM tag_expertise te 
   WHERE te.OwnerUserId = uam.Id 
   ORDER BY te.avg_tag_score DESC, te.tag_usage_count DESC 
   LIMIT 1) as top_expertise_tag,
  (SELECT COUNT(*) 
   FROM tag_expertise te 
   WHERE te.OwnerUserId = uam.Id 
     AND te.avg_tag_score > 5) as high_performing_tags,
  ROUND(AVG(NULLIF(pis.upvote_count, 0)::numeric / NULLIF(pis.downvote_count, 1)), 2) as upvote_downvote_ratio,
  CASE 
    WHEN uam.Reputation > 50000 THEN 'Elite'
    WHEN uam.Reputation > 10000 THEN 'Expert'
    WHEN uam.Reputation > 5000 THEN 'Advanced'
    ELSE 'Intermediate'
  END as reputation_category,
  COALESCE(SUM(pis.linked_count), 0) as total_post_links
FROM user_activity_metrics uam
LEFT OUTER JOIN badge_rankings br ON uam.Id = br.UserId AND br.badge_rank <= 10
LEFT OUTER JOIN post_interaction_stats pis ON uam.Id = pis.OwnerUserId
WHERE EXISTS (
  SELECT 1 
  FROM Posts p2 
  WHERE p2.OwnerUserId = uam.Id 
    AND p2.Score > 10
    AND p2.CreationDate >= '2021-01-01'
)
AND (
  SELECT COUNT(*) 
  FROM Votes v 
  WHERE v.UserId = uam.Id 
    AND v.VoteTypeId IN (2, 3)
) > 50
GROUP BY uam.Id, uam.DisplayName, uam.Location, uam.Reputation, uam.post_count, 
         uam.question_count, uam.answer_count, uam.avg_post_score
HAVING COUNT(DISTINCT br.badge_name) >= 3
  AND SUM(CASE WHEN br.Class IN (1, 2) THEN br.badge_count ELSE 0 END) > 0
ORDER BY 
  uam.Reputation DESC,
  COUNT(DISTINCT br.badge_name) DESC,
  MAX(pis.ViewCount) DESC NULLS LAST
LIMIT 100;
